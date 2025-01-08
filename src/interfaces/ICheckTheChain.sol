// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface ICheckTheChain {
    function checkPrice(
        address token
    ) external view returns (uint256 price, string memory priceStr);
}
