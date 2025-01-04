// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ETH2X} from "../src/ETH2X.sol";

contract ETH2XScript is Script {
    ETH2X public eth2x;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        eth2x = new ETH2X();

        vm.stopBroadcast();
    }
}
