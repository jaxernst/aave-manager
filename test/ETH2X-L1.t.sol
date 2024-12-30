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
        (uint256 totalCollateralBefore, uint256 totalDebtBefore,,,,) = eth2x.getAccountData();
        assertEq(totalCollateralBefore, 0);
        assertEq(totalDebtBefore, 0);

        eth2x.mint{value: 1 ether}(address(1));
        uint256 tokensPerEth = 10000; // The initial exchange rate
        assertEq(eth2x.balanceOf(address(1)), tokensPerEth * 1e18);
        assertEq(eth2x.totalSupply(), tokensPerEth * 1e18);

        (uint256 totalCollateralAfter, uint256 totalDebtAfter,,,,) = eth2x.getAccountData();

        // Depositing 1 ETH should give us 1 aWETH value in collateral (with a 0.05% buffer for Aave vs Uniswap oracle differences)
        assertGt(totalCollateralAfter, eth2x.ethPrice() * 9995 / 10000);
        assertLt(totalCollateralAfter, eth2x.ethPrice() * 10005 / 10000);

        // We haven't borrowed anything yet, so debt should be 0 and leverage ratio should be infinite
        assertEq(totalDebtAfter, 0);
        assertEq(eth2x.getLeverageRatio(), 0);
    }

    function test_Rebalance() public {
        console.log("minting 1 ETH worth of ETH2X tokens");
        eth2x.mint{value: 1 ether}(address(1));
        (uint256 totalCollateralBefore,,,,,) = eth2x.getAccountData();
        assertLt(eth2x.getLeverageRatio(), eth2x.TARGET_RATIO());
        console.log("totalCollateralBefore", totalCollateralBefore);
        console.log("rebalancing...");
        eth2x.rebalance();

        (uint256 totalCollateralAfter, uint256 totalDebtAfter,,,,) = eth2x.getAccountData();

        // We should have 2 ETH in collateral and 1 ETH worth of USDC in debt. Allow a 1% buffer
        console.log("totalCollateralAfter", totalCollateralAfter);
        assertGt(totalCollateralAfter, eth2x.ethPrice() * 195 / 100); // Greater than 1.95 ETH
        assertLt(totalCollateralAfter, eth2x.ethPrice() * 205 / 100); // Less than 2.05 ETH

        console.log("totalDebtAfter", totalDebtAfter);
        assertGt(totalDebtAfter, eth2x.ethPrice() * 95 / 100); // Greater than 0.95 ETH worth of USDC
        assertLt(totalDebtAfter, eth2x.ethPrice() * 105 / 100); // Less than 1.05 ETH worth of USDC

        console.log("afterRatio", eth2x.getLeverageRatio()); // Should be very close to 2
    }
}
