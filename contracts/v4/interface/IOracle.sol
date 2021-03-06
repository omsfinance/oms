pragma solidity 0.4.24;

interface IOracle {
    function getData() external returns (uint256, bool);
}