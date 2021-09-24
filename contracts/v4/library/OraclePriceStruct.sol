pragma solidity 0.4.24;

contract OraclePriceStruct {
    struct OracleInfo {
        address oracleAddress;
        bool isActive;
        bytes32 symbolHash;
        int256 lastPrice; 
    }
}