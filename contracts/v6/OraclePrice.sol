// SPDX-License-Identifier: Unlicensed
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "./interface/KeeperCompatibleInterface.sol";
import "./interface/IOmsPolicy.sol";
import "./interface/EACAggregatorProxy.sol";
import "./library/SafeMath.sol";
import "./common/Ownable.sol";
import "./library/OraclePriceStruct.sol";

contract OraclePrice is Ownable, KeeperCompatibleInterface {
    using SafeMath for uint256;
    
    // Storing all the details of oracle address
    OraclePriceStruct.OracleInfo[] public oracleInfo;
    // OmsPolicy contract address
    address public policyContract;

    // If the current exchange rate is within this fractional distance from the target, no supply
    // update is performed. Fixed point number--same format as the rate.
    // (ie) abs(rate - targetRate) / targetRate < deviationThreshold, then no supply change.
    // DECIMALS Fixed point number.
    uint256 public deviationThreshold;

    // More than this much time must pass between keepers operations.
    uint public immutable interval;
    // Block timestamp of last Keepers operations.
    uint public lastTimeStamp;
    // The number of keepers cycles since inception
    uint public counter;
    
    constructor(OraclePriceStruct.OracleInfo[] memory _oracles, address _policyContract, uint256 _deviationThreshold, uint _updateInterval) public {
        policyContract = _policyContract;
        deviationThreshold = _deviationThreshold;
        
        for(uint256 i=0; i<_oracles.length; i++) {
            OraclePriceStruct.OracleInfo memory oracles = _oracles[i];
            oracleInfo.push(OraclePriceStruct.OracleInfo({
                oracleAddress: oracles.oracleAddress,
                isActive: oracles.isActive,
                symbolHash: oracles.symbolHash,
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
    
    /**
     * Fetching updated price from all oracles and calculating ref rate to update 
     * Target price.
     */
    function updateTargetPrice() internal {
        uint256 length = oracleInfo.length;
        for(uint256 i=0; i<length; i++) {
            OraclePriceStruct.OracleInfo storage oracles = oracleInfo[i];
            if(oracles.isActive == true) {
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
    
    /**
     * @param rate The current exchange rate, an 18 decimal fixed point number.
     * @param targetRate The target exchange rate, an 18 decimal fixed point number.
     * @return If the rate is within the deviation threshold from the target rate, returns true.
     *         Otherwise, returns false.
     */
    function withinDeviationThreshold(uint256 rate, uint256 targetRate) private view returns (bool) {
        uint256 absoluteDeviationThreshold = targetRate.mul(deviationThreshold).div(10**18);

        return
            (rate >= targetRate &&
                rate.sub(targetRate) < absoluteDeviationThreshold) ||
            (rate < targetRate &&
                targetRate.sub(rate) < absoluteDeviationThreshold);
    }
    
    /**
     * @param _pid index number of oracle address.
     * @param _oracle updated oracle address.
     * @param _isActive true if oracle is active otherwise inactive.
     * @param _symbolHash symbolHash of crypto currency.
     */
    function updateOracles(uint256 _pid, address _oracle, bool _isActive, bytes32 _symbolHash) public onlyOwner {
        OraclePriceStruct.OracleInfo storage oracles = oracleInfo[_pid];
        require(oracles.oracleAddress != address(0), "No Oracle Found");
        oracles.oracleAddress = _oracle;
        oracles.isActive = _isActive;
        oracles.symbolHash = _symbolHash;
    }

    /**
     * @param _oracle new oracle address to add in structure.
     * @param _isActive true if oracle is active otherwise inactive.
     * @param _symbolHash symbolHash of crypto currency.
     */
    function addOracles(address _oracle, bool _isActive, bytes32 _symbolHash) public onlyOwner {
        oracleInfo.push(OraclePriceStruct.OracleInfo({
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
     * @notice Sets the deviation threshold fraction. If the exchange rate given by the market
     *         oracle is within this fractional distance from the targetRate, then no supply
     *         modifications are made. DECIMALS fixed point number.
     * @param deviationThreshold_ The new exchange rate threshold fraction.
     */
    function setDeviationThreshold(uint256 deviationThreshold_) external onlyOwner {
        deviationThreshold = deviationThreshold_;
    }
}