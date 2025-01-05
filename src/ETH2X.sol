// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import {IPool} from "@aave/core/contracts/interfaces/IPool.sol";
import {IWETH} from "@aave/core/contracts/misc/interfaces/IWETH.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";

import {ICheckTheChain} from "./interfaces/ICheckTheChain.sol";
import {IV3SwapRouter} from "./interfaces/IV3SwapRouter.sol";

/**
 * @title ETH2X
 * @notice A permissionless system that allows users to easily maintain a 2x leveraged ETH position.
 * @dev The underlying assets (WETH and USDC) are transparently managed in Aave via the `rebalance()` method.
 */
contract ETH2X is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    /*//////////////////////////////////////////////////////////////
                               PARAMETERS
    //////////////////////////////////////////////////////////////*/

    // Local
    uint256 public constant TARGET_RATIO = 2e18; // 2x leverage
    mapping(address => bool) public allowed; // Allowlist for minting (temporary while testing)

    // Uniswap
    address public immutable USDC;
    address public immutable WETH;
    uint24 internal constant POOL_FEE = 500; // 0.05%
    IV3SwapRouter public immutable SWAP_ROUTER;
    ICheckTheChain public immutable CHECK_THE_CHAIN;

    // Aave
    IPool public immutable POOL;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Mint(address indexed to, uint256 amount);
    event Redeem(address indexed to, uint256 amount);
    event Rebalance(uint256 leverageRatio, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientCollateral();
    error NothingToRedeem();
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAllowed() {
        if (owner() == address(0)) {
            // If ownership has been renounced, allow everyone to mint
            _;
        } else {
            // If there is an owner, only allow allowed addresses to mint
            if (!allowed[msg.sender]) {
                revert Unauthorized();
            }
            _;
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _usdc,
        address _weth,
        address _swapRouter,
        address _checkTheChain,
        address _pool,
        address _owner
    ) ERC20("ETH2X", "ETH2X") ERC20Permit("ETH2X") Ownable(_owner) {
        USDC = _usdc;
        WETH = _weth;
        SWAP_ROUTER = IV3SwapRouter(_swapRouter);
        CHECK_THE_CHAIN = ICheckTheChain(_checkTheChain);
        POOL = IPool(_pool);

        // Approve the router to spend USDC and WETH
        TransferHelper.safeApprove(USDC, address(SWAP_ROUTER), type(uint256).max);
        TransferHelper.safeApprove(WETH, address(SWAP_ROUTER), type(uint256).max);

        // Approve the pool to spend USDC and WETH
        TransferHelper.safeApprove(USDC, address(POOL), type(uint256).max);
        TransferHelper.safeApprove(WETH, address(POOL), type(uint256).max);

        // Allow the owner to mint
        allowed[_owner] = true;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow users to mint tokens by sending ETH to the contract
    receive() external payable {
        if (msg.sender != address(WETH)) {
            mint(msg.sender);
        }
    }

    /**
     * @notice Mint ETH2X tokens to the caller
     * @dev We don't need to rebalance internally because worst case, we have more collateral than debt.
     * @param onBehalfOf The address to mint tokens to
     */
    function mint(address onBehalfOf) public payable onlyAllowed {
        // Figure out how many tokens the caller should get based on the amount of ETH they deposit
        uint256 amount = calculateTokensToMint(msg.value);

        // Supply ETH to Aave and recieve equal amount of aWETH
        IWETH(WETH).deposit{value: msg.value}();
        POOL.supply(WETH, msg.value, address(this), 0);

        // Mint tokens to the caller to represent ownership of the pool
        _mint(onBehalfOf, amount);
        emit Mint(onBehalfOf, amount);
    }

    /**
     * @notice Burn ETH2X tokens to redeem underlying ETH
     * @dev We DO need to rebalance internally here, because it's possible for somebody to withdraw enough ETH to
     *      where the USDC loan gets liquidated.
     * @param amount The amount of ETH2X tokens to burn
     */
    function redeem(uint256 amount) external {
        uint256 ethToRedeem = calculateEthToRedeem(amount);

        // Burn tokens from the caller which represents their ownership of the pool decreasing.
        // This includes a check to ensure the caller has enough tokens
        _burn(msg.sender, amount);

        if (ethToRedeem == 0) {
            revert NothingToRedeem();
        }

        (uint256 totalCollateral, uint256 totalDebt,,,,) = getAccountData();
        uint256 ethWorthOfPool = ((totalCollateral - totalDebt) * 1e18) / ethPrice();

        // Check if we have enough collateral to cover the withdrawal
        if (ethWorthOfPool < ethToRedeem) {
            revert InsufficientCollateral();
        }

        // The most amount of times we'll need to repay the loan is 3 times due to Aave's LTV limits
        // For simplicity (not efficiency), we'll just repay the loan in 3 equal parts every time
        _withdrawEthSwapForUsdcAndRepay(ethToRedeem / 3);
        _withdrawEthSwapForUsdcAndRepay(ethToRedeem / 3);
        _withdrawEthSwapForUsdcAndRepay(ethToRedeem / 3);

        // Withdraw the corresponding amount of WETH from Aave
        POOL.withdraw(WETH, ethToRedeem, address(this));

        // Unwrap the WETH and transfer it to the caller
        IWETH(WETH).withdraw(ethToRedeem);
        TransferHelper.safeTransferETH(msg.sender, ethToRedeem);

        emit Redeem(msg.sender, ethToRedeem);
    }

    function rebalance() public {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = getAccountData();
        uint256 leverageRatio = getLeverageRatio();

        // Goal is for totalCollateralBase to always be (TARGET_RATIO / 1e18) * totalDebtBase
        // For 2x leverage, collateral should be $100 worth of ETH for every $50 worth of borrowed USDC

        // Examples of how rebalancing should work:
        // If collateral = $3000 and debt = $0, we want to _borrowUsdcSwapForEthAndSupply(1500). That gets us to $4500 collateral and $1500 debt (not 2x yet)
        // If collateral = $4500 and debt = $1500, we want to _borrowUsdcSwapForEthAndSupply(1500). That gets us to $6000 collateral and $3000 debt (2x leverage!)
        // If collateral = $2500 and debt = $1500, we want to _withdrawEthSwapForUsdcAndRepay(500 / ethPrice()). That gets us to $2000 collateral and $1000 debt (2x leverage)

        if (leverageRatio > TARGET_RATIO) {
            uint256 amountToBorrow = ((totalCollateralBase / ((TARGET_RATIO) / 1e18)) - totalDebtBase) / 100;
            _borrowUsdcSwapForEthAndSupply(amountToBorrow);
        } else {
            uint256 amountToWithdraw = totalCollateralBase - (totalDebtBase * TARGET_RATIO / 1e18);
            _withdrawEthSwapForUsdcAndRepay(amountToWithdraw);
        }

        emit Rebalance(leverageRatio, block.timestamp);
    }

    function setAllowed(address user, bool allowed_) external onlyOwner {
        allowed[user] = allowed_;
    }

    /**
     * @notice Returns the user account data across all the reserves
     * @return totalCollateralBase The total collateral of the user in the base currency used by the price feed
     * @return totalDebtBase The total debt of the user in the base currency used by the price feed
     * @return availableBorrowsBase The borrowing power left of the user in the base currency used by the price feed
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of The user
     * @return healthFactor The current health factor of the user
     */
    function getAccountData()
        public
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return POOL.getUserAccountData(address(this));
    }

    function getLeverageRatio() public view returns (uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = getAccountData();

        if (totalDebtBase == 0) {
            return type(uint256).max; // Return max value to indicate infinite leverage
        }

        // Multiply by 1e18 before division to maintain precision
        return (totalCollateralBase * 1e18) / totalDebtBase;
    }

    /**
     * @notice Calculate the amount of ETH2X tokens to mint based on the amount of ETH deposited.
     * @param depositAmount The amount of ETH to deposit
     * @return The amount of tokens to mint
     */
    function calculateTokensToMint(uint256 depositAmount) public view returns (uint256) {
        (uint256 totalCollateralBefore, uint256 totalDebtBefore,,,,) = getAccountData();
        uint256 tokenSupply = totalSupply();

        // Calculate amount of tokens to mint based on the proportional ownership
        uint256 amount;
        if (tokenSupply == 0) {
            // First deposit - set initial exchange rate of 10k tokens = 1 ETH
            amount = depositAmount * 10000;
        } else {
            // Calculate the net value (collateral - debt) before and after deposit
            uint256 netValueBefore = totalCollateralBefore - totalDebtBefore;
            uint256 depositAmountValue = (depositAmount) * ethPrice();
            uint256 percentageContribution = (depositAmountValue) / netValueBefore;

            // Mint tokens proportional to the value added compared to existing value
            amount = (percentageContribution * tokenSupply) / 1e18;
        }

        return amount;
    }

    /**
     * @notice Calculate the amount of ETH to redeem based on the amount of ETH2X tokens burned.
     * @param redeemAmount The amount of ETH2X tokens to burn in exchange for the underlying ETH
     * @return The amount of ETH to redeem
     */
    function calculateEthToRedeem(uint256 redeemAmount) public view returns (uint256) {
        (uint256 collateral, uint256 debt,,,,) = getAccountData();

        // Calculate the percentage of the pool that the tokens represent
        uint256 percentageOwned = (redeemAmount * 1e18) / totalSupply();

        // If we had to put all assets into ETH, how much would it be worth?
        uint256 value = collateral - debt;

        // How much of that value does the redeemer own?
        uint256 redeemerValue = value * percentageOwned;

        // How much ETH is that worth?
        uint256 amount = redeemerValue / ethPrice();

        // Take a 1% haircut to account for fees/slippage, and always safer to round down
        return amount - (amount / 100);
    }

    /// @return Price of ETH in USDC with 12 digits of precision
    function ethPrice() public view returns (uint256) {
        (uint256 price,) = CHECK_THE_CHAIN.checkPrice(WETH);
        // Convert to 12 digits of precision to match Aave's price feed
        return price * 100;
    }

    function _borrowUsdcSwapForEthAndSupply(uint256 amountToBorrow) internal {
        // 1. Borrow USDC (adjust for it being 6 decimals)
        POOL.borrow(USDC, amountToBorrow, 2, 0, address(this));

        // 2. Swap USDC for WETH on Uniswap
        uint256 expectedEthAmountOut = 0; // TODO: Use a live price feed for this
        uint256 amountOut = _swap(USDC, WETH, amountToBorrow, expectedEthAmountOut);

        // 3. Deposit new WETH into Aave
        POOL.supply(WETH, amountOut, address(this), 0);
    }

    function _withdrawEthSwapForUsdcAndRepay(uint256 amountToWithdraw) internal {
        // 1. Withdraw enough ETH from Aave
        POOL.withdraw(WETH, amountToWithdraw, address(this));

        // 2. Swap WETH for USDC on Uniswap
        uint256 expectedUsdcAmountOut = 0; // TODO: Use a live price feed for this
        uint256 amountOut = _swap(WETH, USDC, amountToWithdraw, expectedUsdcAmountOut);

        // 3. Repay the loan
        POOL.repay(USDC, amountOut, 2, address(this));
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 expectedAmountOut)
        internal
        returns (uint256 amountOut)
    {
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: POOL_FEE,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: expectedAmountOut - (expectedAmountOut / 200), // Allow 0.1% slippage
            sqrtPriceLimitX96: 0 // TODO: Figure out what this is
        });

        return SWAP_ROUTER.exactInputSingle(params);
    }
}
