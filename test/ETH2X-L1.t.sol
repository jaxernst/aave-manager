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
        uint256 tokensPerEth = 1000; // The initial exchange rate
        assertEq(eth2x.balanceOf(address(1)), tokensPerEth * 1e18);
        assertEq(eth2x.totalSupply(), tokensPerEth * 1e18);

        (uint256 totalCollateralAfter, uint256 totalDebtAfter,,,,) = eth2x.getAccountData();
        // Depositing 1 ETH should give us 1 aWETH value in collateral (with a 0.05% buffer for Aave vs Uniswap oracle differences)
        assertGt(totalCollateralAfter, eth2x.ethPrice() * 9995 / 10000);
        assertLt(totalCollateralAfter, eth2x.ethPrice() * 10005 / 10000);
        // We haven't borrowed anything yet, so debt should be 0
        assertEq(totalDebtAfter, 0);
    }
}
