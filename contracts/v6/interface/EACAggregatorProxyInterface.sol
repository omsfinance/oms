// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.12;

interface EACAggregatorProxyInterface {
    function latestAnswer() external view returns (int256); 
    function decimals() external view returns (uint8);
}