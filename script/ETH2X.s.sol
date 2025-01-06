// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {ETH2X} from "../src/ETH2X.sol";

contract ETH2XScript is Script {
    ETH2X public eth2x;

    function setUp() public {}

    // Below addresses are for Base
    function run() public {
        vm.startBroadcast();

        address _usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address _weth = 0x4200000000000000000000000000000000000006;

        // https://docs.uniswap.org/contracts/v3/reference/deployments
        address _swapRouter = 0x2626664c2603336E57B271c5C0b26F421741e481;

        // https://aave.com/docs/resources/addresses
        address _priceOracle = 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156;
        address _pool = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

        address _owner = 0x179A862703a4adfb29896552DF9e307980D19285;

        eth2x = new ETH2X(_usdc, _weth, _swapRouter, _priceOracle, _pool, _owner);

        vm.stopBroadcast();
    }
}

// forge verify-contract \
//     --chain-id 8453 \
//     --num-of-optimizations 200 \
//     --watch \
//     --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address)" 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 0x4200000000000000000000000000000000000006 0x2626664c2603336E57B271c5C0b26F421741e481 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5 0x179A862703a4adfb29896552DF9e307980D19285) \
//     --compiler-version v0.8.28+commit.7893614a \
//     0x271f0FA3852c9bB8940426A74cb987a354ED2553 \
//     src/ETH2X.sol:ETH2X
