// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./interface/KeeperCompatibleInterface.sol";
import "./interface/IOmsPolicy.sol";
import "./interface/EACAggregatorProxy.sol";
import "./library/SafeMath.sol";
import "./common/Ownable.sol";
import "./library/OraclePriceStruct.sol";

contract OraclePrice is Ownable, KeeperCompatibleInterface {
    using SafeMath for uint256;
    
    OraclePriceStruct.OracleInfo[] public oracleInfo;
    address public policyContract;
    uint256 public deviationThreshold;
    uint public immutable interval;
    uint public lastTimeStamp;
    uint public counter;
    
    constructor(OraclePriceStruct.OracleInfo[] memory _oracles, address _policyContract, uint256 _deviationThreshold, uint _updateInterval) public {
        policyContract = _policyContract;
        deviationThreshold = _deviationThreshold;
        
        for(uint256 i=0; i<_oracles.length; i++) {
            OraclePriceStruct.OracleInfo memory oracles = _oracles[i];
            oracleInfo.push(OraclePriceStruct.OracleInfo({
                oracleAddress: oracles.oracleAddress,
                status: oracles.status,
                symbolHash: oracles.symbolHash,
                lastPrice: 0
            }));
        }

        interval = _updateInterval;
        lastTimeStamp = block.timestamp;
        counter = 0;
    }
    
    function getOraclePriceInUsd(uint256 _oracleId) public view returns (int256) {
        OraclePriceStruct.OracleInfo storage oracles = oracleInfo[_oracleId];
        int256 latestPrice = EACAggregatorProxy(oracles.oracleAddress).latestAnswer();
        return latestPrice;
    }

    function checkUpkeep(bytes calldata checkData) external override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(bytes calldata performData) external override {
        bool upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
        require(upkeepNeeded == true, "Can Not call this method at this time");

        lastTimeStamp = block.timestamp;
        counter = counter + 1;

        updateTargetPrice();
    }
    
    function updateTargetPrice() internal {
        uint256 length = oracleInfo.length;
        for(uint256 i=0; i<length; i++) {
            OraclePriceStruct.OracleInfo storage oracles = oracleInfo[i];
            if(oracles.status == true) {
                int256 latestPrice = EACAggregatorProxy(oracles.oracleAddress).latestAnswer();
                uint8 decimals = EACAggregatorProxy(oracles.oracleAddress).decimals();
                uint256 restDec = SafeMath.sub(18, uint256(decimals));
                latestPrice = int256(SafeMath.mul(uint256(latestPrice), 10**restDec));
                oracles.lastPrice = latestPrice;
            }
        }
        uint256 targetRate = IOmsPolicy(policyContract).targetPrice();
        uint256 rate  = IOmsPolicy(policyContract).calculateReferenceRate();
        bool shouldUpdatePrice = withinDeviationThreshold(rate, targetRate);
        
        if(shouldUpdatePrice) {
            IOmsPolicy(policyContract).setTargetPrice(rate);
        }
    }
    
    function withinDeviationThreshold(uint256 rate, uint256 targetRate) private view returns (bool) {
        uint256 absoluteDeviationThreshold = targetRate.mul(deviationThreshold).div(10**18);

        return
            (rate >= targetRate &&
                rate.sub(targetRate) < absoluteDeviationThreshold) ||
            (rate < targetRate &&
                targetRate.sub(rate) < absoluteDeviationThreshold);
    }
    
    function updateOracles(uint256 _pid, address _oracle, bool _status, bytes32 _symbolHash) public onlyOwner {
        OraclePriceStruct.OracleInfo storage oracles = oracleInfo[_pid];
        require(oracles.oracleAddress != address(0), "No Oracle Found");
        oracles.oracleAddress = _oracle;
        oracles.status = _status;
        oracles.symbolHash = _symbolHash;
    }

    function addOracles(address _oracle, bool _status, bytes32 _symbolHash) public onlyOwner {
        oracleInfo.push(OraclePriceStruct.OracleInfo({
                oracleAddress: _oracle,
                status: _status,
                symbolHash: _symbolHash,
                lastPrice: 0
            }));
    }
    
    function updatePolicy(address _policy) public onlyOwner {
        policyContract = _policy;
    }
    
    function setDeviationThreshold(uint256 deviationThreshold_) external onlyOwner {
        deviationThreshold = deviationThreshold_;
    }
}