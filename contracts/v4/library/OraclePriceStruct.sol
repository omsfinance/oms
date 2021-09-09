pragma solidity 0.4.24;

contract OraclePriceStruct {
    struct OracleInfo {
        address oracleAddress;
        bool status;
        bytes32 symbolHash;
        int256 lastPrice; 
    }
}