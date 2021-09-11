pragma solidity 0.6.12;

contract OraclePriceStruct {
    struct OracleInfo {
        address oracleAddress;
        bool status;
        bytes32 symbolHash;
        int256 lastPrice; 
    }
}