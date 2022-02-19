// SPDX-License-Identifier: Unlicensed
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "./interface/KeeperCompatibleInterface.sol";
import "./interface/IOmsPolicy.sol";
import "./interface/EACAggregatorProxy.sol";
import "./library/SafeMath.sol";
import "./common/Ownable.sol";

contract OraclePrice is Ownable, KeeperCompatibleInterface {
    using SafeMath for uint256;

    struct PriceLog {
        int256 lastUpdatedPrice;
    }

    struct AverageLog {
        int256 averageMovement;
        int256 referenceRate;
    }

    struct OracleInfo {
        address oracleAddress;
        bool isActive;
        bytes32 symbolHash;
        int256 lastPrice; 
    }
    
    event LogTargetPriceUpdated(uint256 indexed performUpkeepCycle, uint256 timestampSec, int256 averageMovement, uint256 oldReferenceRate, uint256 newReferenceRate);
    event LogReferenceRateDataUsed(uint256 indexed performUpkeepCycle, uint256 timestampSec, address oracleAddress, int256 oldPrice, int256 newPrice);

    // Storing all the details of oracle address
    OracleInfo[] public oracleInfo;

    // OmsPolicy contract address
    address public policyContract;

    // More than this much time must pass between keepers operations.
    uint public immutable interval;

    // Block timestamp of last Keepers operations.
    uint public lastTimeStamp;

    // The number of keepers cycles since inception
    uint public counter;

    // PriceLog represents last price of each currency
    mapping (address => PriceLog) public priceLog;

    // AverageLog represents last average and ref rate of currency
    AverageLog public averageLog;
    
    constructor(OracleInfo[] memory _oracles, address _policyContract, uint _updateInterval) public {
        policyContract = _policyContract;
        
        for(uint256 i=0; i<_oracles.length; i++) {
            OracleInfo memory oracle = _oracles[i];
            oracleInfo.push(OracleInfo({
                oracleAddress: oracle.oracleAddress,
                isActive: oracle.isActive,
                symbolHash: oracle.symbolHash,
                lastPrice: 0
            }));
        }

        interval = _updateInterval;
        lastTimeStamp = 0;
        counter = 0;
    }

    function getOracleInfoCount() public view returns (uint256) {
        return oracleInfo.length;
    }
    
    /**
     * @param _oracleId index number of oracle address.
     * Fetching updated price of perticular oracles from chainlink. 
     */
    function getOraclePriceInUsd(uint256 _oracleId) public view returns (int256) {
        OracleInfo storage oracle = oracleInfo[_oracleId];
        int256 latestPrice = EACAggregatorProxy(oracle.oracleAddress).latestAnswer();
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

    // calculate average movement and ReferenceRate from all currency price 
    function calculateReferenceRate() internal returns(uint256) {
        uint256 oracleInfoCount = oracleInfo.length;
        
        int256 sumPrice = 0;
        int256 decimals = 1e18;
        uint256 activeOracle = 0;
        for(uint256 i=0; i<oracleInfoCount; i++) {
            OracleInfo storage oracle = oracleInfo[i];
            if(oracle.isActive == true) {
                PriceLog storage pricelog = priceLog[oracle.oracleAddress];
                sumPrice = addUnderFlow(sumPrice, divUnderFlow(mulUnderFlow(subUnderFlow(oracle.lastPrice, pricelog.lastUpdatedPrice), 100000), oracle.lastPrice));
                if(pricelog.lastUpdatedPrice == 0) {
                    sumPrice = 0;
                }

                emit LogReferenceRateDataUsed(counter, lastTimeStamp, oracle.oracleAddress, pricelog.lastUpdatedPrice, oracle.lastPrice);
                
                pricelog.lastUpdatedPrice = oracle.lastPrice;
                activeOracle = activeOracle.add(1);
            }
        }

        int256 avgMovement = divUnderFlow(sumPrice, int256(activeOracle));
        if(averageLog.referenceRate == 0) {
            averageLog.referenceRate = decimals;
        }
        int256 refRate = divUnderFlow(mulUnderFlow(averageLog.referenceRate, addUnderFlow(decimals, divUnderFlow(mulUnderFlow(decimals, avgMovement), 100000))), decimals);

        averageLog.averageMovement = avgMovement;
        averageLog.referenceRate = refRate;

        return uint256(refRate);
    }
    
    /**
     * Fetching updated price from all oracles and calculating ref rate to update 
     * Target price.
     */
    function updateTargetPrice() internal {
        uint256 length = oracleInfo.length;
        for(uint256 i=0; i<length; i++) {
            OracleInfo storage oracle = oracleInfo[i];
            if(oracle.isActive == true) {
                int256 latestPrice = EACAggregatorProxy(oracle.oracleAddress).latestAnswer();
                uint8 decimals = EACAggregatorProxy(oracle.oracleAddress).decimals();
                uint256 restDec = SafeMath.sub(18, uint256(decimals));
                latestPrice = int256(SafeMath.mul(uint256(latestPrice), 10**restDec));
                oracle.lastPrice = latestPrice;
            }
        }
    
        uint256 oldTargetPrice = IOmsPolicy(policyContract).targetPrice();
        uint256 newTargetPrice = calculateReferenceRate();

        IOmsPolicy(policyContract).setTargetPrice(newTargetPrice);
        
        emit LogTargetPriceUpdated(counter, lastTimeStamp, averageLog.averageMovement, oldTargetPrice, newTargetPrice);
    }
    
    /**
     * @param _pid index number of oracle address.
     * @param _oracle updated oracle address.
     * @param _isActive true if oracle is active otherwise inactive.
     * @param _symbolHash symbolHash of crypto currency.
     */
    function updateOracle(uint256 _pid, address _oracle, bool _isActive, bytes32 _symbolHash) public onlyOwner {
        OracleInfo storage oracle = oracleInfo[_pid];
        require(oracle.oracleAddress != address(0), "No Oracle Found");
        oracle.oracleAddress = _oracle;
        oracle.isActive = _isActive;
        oracle.symbolHash = _symbolHash;
    }

    /**
     * @param _oracle new oracle address to add in structure.
     * @param _isActive true if oracle is active otherwise inactive.
     * @param _symbolHash symbolHash of crypto currency.
     */
    function addOracle(address _oracle, bool _isActive, bytes32 _symbolHash) public onlyOwner {
        oracleInfo.push(OracleInfo({
                oracleAddress: _oracle,
                isActive: _isActive,
                symbolHash: _symbolHash,
                lastPrice: 0
            }));
    }
    
    /**
     * @param _policy new policy address.
     */
    function updatePolicy(address _policy) public onlyOwner {
        policyContract = _policy;
    }

    /**
    * @dev Subtracts two int256 variables.
    */
    function subUnderFlow(int256 a, int256 b)
            internal
            pure
            returns (int256)
    {
        int256 c = a - b;
        return c;
    }

    /**
     * @dev Adds two int256 variables and fails on overflow.
     */
    function addUnderFlow(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        int256 c = a + b;
        return c;
    }

    /**
    * @dev Division of two int256 variables and fails on overflow.
     */
    function divUnderFlow(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        require(b != 0, "div overflow");

        // Solidity already throws when dividing by 0.
        return a / b;
    }

    /**
     * @dev Multiplies two int256 variables and fails on overflow.
     */
    function mulUnderFlow(int256 a, int256 b)
        internal
        pure
        returns (int256)
    {
        int256 c = a * b;
        return c;
    }
}