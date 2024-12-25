// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IPool} from "@aave/core/contracts/interfaces/IPool.sol";
import {IWrappedTokenGatewayV3} from "@aave/periphery/contracts/misc/interfaces/IWrappedTokenGatewayV3.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * @title
 *
 * When deposit() is called, this contract should deposit {msg.value} into Aave and borrow USDC at {tbd} rate.
 * With the USDC, the contract should swap it for ETH on Uniswap.
 * The goal is to maintain a 2x leveraged position in ETH, which anybody can help maintain via rebalance().
 *
 * Goal should be to have $2 worth of ETH for every 1 USDC in the contract.
 */
contract ETH2X is ERC20 {
    uint256 public constant TARGET_RATIO = 2; // 2x leverage
    uint256 public lastRebalance;

    address public immutable USDC;
    IPool public immutable POOL;
    IWrappedTokenGatewayV3 public immutable WRAPPED_TOKEN_GATEWAY;

    constructor() ERC20("ETH2X", "ETH2X") {
        USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        POOL = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
        WRAPPED_TOKEN_GATEWAY = IWrappedTokenGatewayV3(0xA434D495249abE33E031Fe71a969B81f3c07950D);
    }

    function deposit() public payable {
        // Supply ETH to Aave and recieve equal amount of aWETH
        WRAPPED_TOKEN_GATEWAY.depositETH{value: msg.value}(address(0), address(this), 0);

        /**
         * TODO: Determine amount of tokens to mint
         * Options: Give the caller tokens based on...
         * 1. the price of ETH at the time of deposit
         * 2. the amount of ETH deposited compared to the total amount of aWETH in the contract
         * 3. ??
         */

        // Mint tokens to the caller to represent ownership of the pool
        uint256 amount = 1000e18;
        _mint(msg.sender, amount);

        // Rebalance the position
        rebalance();
    }

    function rebalance() public {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = getAccountData();

        // Goal is to have totalCollateralBase be (totalDebtBase * TARGET_RATIO)
        // E.g. for 2x leverage, totalCollateralBase should be $100 worth of ETH for every $50 worth of USDC borrowed

        if (getLeverageRatio() < TARGET_RATIO) {
            // Borrow more USDC
            uint256 amountToBorrow = totalDebtBase * TARGET_RATIO - totalCollateralBase;
            POOL.borrow(USDC, amountToBorrow, 2, 0, address(this));

            // TODO: Buy ETH on Uniswap
            // ...

            // Deposit new ETH into Aave
            WRAPPED_TOKEN_GATEWAY.depositETH{value: address(this).balance}(address(0), address(this), 0);
        } else {
            // TODO: Sell ETH and repay USDC
        }

        lastRebalance = block.timestamp;
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
        return totalCollateralBase / totalDebtBase;
    }
}
