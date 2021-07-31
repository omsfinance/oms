// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.12;

interface OmsPolicy {
    function setTargetPrice(uint256 _targetPrice) external;
    function targetPrice() external view returns (uint256); 
}