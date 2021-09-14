pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;

import "../library/OraclePriceStruct.sol";

interface IOraclePrice {
    function getOracleInfoCount() external view returns (uint256);
    function oracleInfo(uint256 _pid) external view returns (OraclePriceStruct.OracleInfo memory);
}