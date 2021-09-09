pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;

import "../library/OraclePriceStruct.sol";

interface IOraclePrice {
    function oracleInfo() external view returns (OraclePriceStruct.OracleInfo[] memory);
}