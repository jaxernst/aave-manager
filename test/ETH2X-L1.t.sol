// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ETH2X} from "../src/ETH2X-L1.sol";

contract ETH2XTest is Test {
    ETH2X public eth2x;

    function setUp() public {
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
}
