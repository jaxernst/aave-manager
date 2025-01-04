// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IPool} from "@aave/core/contracts/interfaces/IPool.sol";
import {Strings} from "@openzeppelin/utils/Strings.sol";

import {ETH2X} from "../src/ETH2X-L1.sol";

contract ETH2XTest is Test {
    ETH2X public eth2x;

    function setUp() public {
        vm.createSelectFork("mainnet", 21512799);
        eth2x = new ETH2X();
    }

    function test_ETH2X() public view {
        assertEq(eth2x.name(), "ETH2X");
        assertEq(eth2x.symbol(), "ETH2X");
    }

    function test_DivisionPrecision() public pure {
        uint256 totalCollateralBase = 5700811217251335;
        uint256 totalDebtBase = 2898887940798631;

        // I originally expected this to be 1.96* but Solidity doesn't support decimals so it stops at 1
        uint256 baseRatio = totalCollateralBase / totalDebtBase;
        assertEq(baseRatio, 1);

        // We have to multiply the numerator by 1e18 to maintain precision
        uint256 preciseRatio = (totalCollateralBase * 1e18) / totalDebtBase;
        assertEq(preciseRatio, 1966551082233549994);
    }

    function test_GetPriceOnchain() public view {
        uint256 price = eth2x.ethPrice();
        assertEq(price, 339988224400);
    }

    function test_CheckDigits() public view {
        // Aave's price feed has 12 digits
        // CheckTheChain returns prices with 10 digits
        // Uniswap uses 18 digits...
        uint256 a = eth2x.ethPrice();
        IPool pool = eth2x.POOL();
        (uint256 b, uint256 c,,,,) = pool.getUserAccountData(0x65c4C0517025Ec0843C9146aF266A2C5a2D148A2);

        // Convert numbers to strings and compare lengths
        assertEq(bytes(Strings.toString(a)).length, 12);
        assertEq(bytes(Strings.toString(b)).length, 16);
        assertEq(bytes(Strings.toString(c)).length, 16);
    }

    function test_Deposit() public {
        address user1 = address(1);
        address user2 = address(2);

        (uint256 totalCollateralBefore, uint256 totalDebtBefore,,,,) = eth2x.getAccountData();
        assertEq(totalCollateralBefore, 0);
        assertEq(totalDebtBefore, 0);

        eth2x.mint{value: 1 ether}(user1);
        uint256 initialTokensPerEth = 10000e18; // The initial exchange rate
        assertEq(eth2x.balanceOf(user1), initialTokensPerEth);
        assertEq(eth2x.totalSupply(), initialTokensPerEth);

        (uint256 totalCollateralAfter, uint256 totalDebtAfter,,,,) = eth2x.getAccountData();

        // Depositing 1 ETH should give us 1 aWETH value in collateral (with a 0.05% buffer for Aave vs Uniswap oracle differences)
        assertGt(totalCollateralAfter, eth2x.ethPrice() * 9995 / 10000);
        assertLt(totalCollateralAfter, eth2x.ethPrice() * 10005 / 10000);

        // We haven't borrowed anything yet, so debt should be 0 and leverage ratio should be infinite
        assertEq(totalDebtAfter, 0);
        assertEq(eth2x.getLeverageRatio(), type(uint256).max);

        // Deposit 1 ETH for the second user, should get roughly the same amount of tokens since it matches the pool value
        uint256 tokensToMint2 = eth2x.calculateTokensToMint(1 ether);
        assertGt(tokensToMint2, initialTokensPerEth * 99 / 100);
        assertLt(tokensToMint2, initialTokensPerEth * 101 / 100);

        // Actually deposit the ETH and check that the correct amount of tokens were minted
        eth2x.mint{value: 1 ether}(user2);
        assertEq(eth2x.balanceOf(user2), tokensToMint2);
    }

    function test_Rebalance() public {
        eth2x.mint{value: 1 ether}(address(1));
        // Sometimes more than 1 rebalance is needed to get to the target leverage ratio because of Aave LTV limits
        // Should only be the case during the initial deposit, and after big deposits
        eth2x.rebalance();
        eth2x.rebalance();
        eth2x.rebalance();

        // Expect the leverage ratio to be 2x (with a 1% buffer)
        assertGt(eth2x.getLeverageRatio(), eth2x.TARGET_RATIO() * 99 / 100);
        assertLt(eth2x.getLeverageRatio(), eth2x.TARGET_RATIO() * 101 / 100);

        // Now let's deposit 100 ETH
        eth2x.mint{value: 100 ether}(address(1));

        // Expect the leverage ratio to be >2x
        assertGt(eth2x.getLeverageRatio(), eth2x.TARGET_RATIO() * 99 / 100);

        eth2x.rebalance();
        eth2x.rebalance();
        eth2x.rebalance();

        // Expect the leverage ratio to be 2x (with a 1% buffer)
        assertGt(eth2x.getLeverageRatio(), eth2x.TARGET_RATIO() * 99 / 100);
        assertLt(eth2x.getLeverageRatio(), eth2x.TARGET_RATIO() * 101 / 100);
    }

    function test_Redeem() public {
        // TODO: Test with multiple users
        address user = address(1);
        address user2 = address(2);

        uint256 initialUserBalance = user.balance;
        eth2x.mint{value: 1 ether}(user);
        uint256 initialTokensPerEth = 10000e18; // The initial exchange rate
        uint256 tokenBalance = eth2x.balanceOf(user);
        assertEq(tokenBalance, initialTokensPerEth);
        eth2x.mint{value: 1 ether}(user2);

        eth2x.rebalance();
        eth2x.rebalance();
        eth2x.rebalance();

        // Calculate the amount of ETH to redeem (should be within 1.5% of 1 ETH due to protocol fees)
        uint256 ethToRedeem = eth2x.calculateEthToRedeem(tokenBalance);
        assertGt(ethToRedeem, 1 ether * 985 / 1000);
        assertLt(ethToRedeem, 1 ether);

        // Burn the tokens and redeem underlying ETH
        vm.prank(user);
        eth2x.redeem(tokenBalance);

        // Check that the user received the correct amount of ETH
        assertEq(user.balance, initialUserBalance + ethToRedeem);

        eth2x.rebalance();

        // There should still be ~2 ETH of collateral and ~1 ETH of debt becuase of the 2nd buyer
        (uint256 totalCollateralAfter, uint256 totalDebtAfter,,,,) = eth2x.getAccountData();
        assertGt(totalCollateralAfter, 2 * eth2x.ethPrice() * 99 / 100);
        assertLt(totalCollateralAfter, 2 * eth2x.ethPrice() * 101 / 100);
        assertGt(totalDebtAfter, eth2x.ethPrice() * 99 / 100);
        assertLt(totalDebtAfter, eth2x.ethPrice() * 101 / 100);
    }
}
