pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;

import "./library/SafeMath.sol";
import "./library/SafeMathInt.sol";
import "./interface/IERC20.sol";
import "./interface/IOracle.sol";
import "./interface/IOraclePrice.sol";
import "./interface/UInt256Lib.sol";
import "./common/Initializable.sol";
import "./common/Ownable.sol";
import "./Oms.sol";
import "./library/OraclePriceStruct.sol";

contract OmsPolicy is Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;

    event LogRebase(
        uint256 indexed epoch,
        uint256 exchangeRate,
        int256 requestedSupplyAdjustment,
        uint256 timestampSec
    );

    event LogTargetPrice(
        uint256 lastTargetPrice,
        uint256 newTargetPrice,
        uint256 timestampSec
    );

    struct PriceLog {
        int256 lastUpdatedPrice;
    }

    struct AverageLog {
        int256 averageMovement;
        int256 referenceRate;
    }

    // PriceLog represents last price of each currency
    mapping (address => PriceLog) public priceLog;
    // AverageLog represents last average and ref rate of currency
    AverageLog public averageLog;

    Oms public oms;
    // Address of oraclePrice contract
    IOraclePrice public oraclePrice;

    // Market oracle provides the token/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e18 it would mean 1 Oms is trading for $1.50.
    IOracle public marketOracle;

    // If the current exchange rate is within this fractional distance from the target, no supply
    // update is performed. Fixed point number--same format as the rate.
    // (ie) abs(rate - targetRate) / targetRate < deviationThreshold, then no supply change.
    // DECIMALS Fixed point number.
    uint256 public deviationThreshold;

    // The rebase lag parameter, used to dampen the applied supply adjustment by 1 / rebaseLag
    // Check setRebaseLag comments for more details.
    // Natural number, no decimal places.
    uint256 public rebaseLag;

    // More than this much time must pass between rebase operations.
    uint256 public minRebaseTimeIntervalSec;

    // Block timestamp of last rebase operation
    uint256 public lastRebaseTimestampSec;

    // The rebase window begins this many seconds into the minRebaseTimeInterval period.
    // For example if minRebaseTimeInterval is 24hrs, it represents the time of day in seconds.
    uint256 public rebaseWindowOffsetSec;

    // The length of the time window where a rebase operation is allowed to execute, in seconds.
    uint256 public rebaseWindowLengthSec;

    // The number of rebase cycles since inception
    uint256 public epoch;

    uint256 private constant DECIMALS = 18;

    // Due to the expression in computeSupplyDelta(), MAX_RATE * MAX_SUPPLY must fit into an int256.
    // Both are 18 decimals fixed point numbers.
    uint256 private constant MAX_RATE = 2 * 10**DECIMALS;
    // MAX_SUPPLY = MAX_INT256 / MAX_RATE
    uint256 private constant MAX_SUPPLY = ~(uint256(1) << 255) / MAX_RATE;

    // target rate 1
    uint256 private constant TARGET_RATE = 1 * 10**DECIMALS;

    // last target price
    uint256 public lastTargetPrice = 1 * 10**DECIMALS;

    // whitelist admin
    mapping(address => bool) public admins;

    // This module orchestrates the rebase execution and downstream notification.
    address public orchestrator;

    modifier onlyOrchestrator() {
        require(msg.sender == orchestrator, 'Only Orchestrator can call this function');
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender] == true, "Not admin role");
        _;
    }

    // set Admin
    function setAdmin(address _admin, bool _status)
        external
        onlyOwner
    {
        require(admins[_admin] != _status, "already admin role");
        admins[_admin] = _status;
    }

    // set target price
    function setTargetPrice(uint256 _targetPrice)
        external
        onlyAdmin
    {
        lastTargetPrice = TARGET_RATE;
        TARGET_RATE = _targetPrice;
        emit LogTargetPrice(lastTargetPrice, TARGET_RATE, block.timestamp);
    }
    
    // set oracle price address
    function setOraclePriceAddress(address _oraclePrice)
        external
        onlyAdmin
    {
        oraclePrice = IOraclePrice(_oraclePrice);
    }

    // return current target price
    function targetPrice() 
       external 
       view 
       returns (uint256) 
    {
       return TARGET_RATE;
    }

    // calculate average movement and ReferenceRate from all currency price 
    function calculateReferenceRate() external onlyAdmin returns(uint256) {
        require(msg.sender == address(oraclePrice), "Only OraclePrice can call this method");
        uint256 oracleInfoCount = oraclePrice.getOracleInfoCount();
        
        int256 sumPrice = 0;
        int256 decimals = 1e18;
        uint256 activeOracle = 0;
        for(uint256 i=0; i<oracleInfoCount; i++) {
            OraclePriceStruct.OracleInfo memory oracles = oraclePrice.oracleInfo(i);
            if(oracles.status == true) {
                PriceLog storage pricelog = priceLog[oracles.oracleAddress];
                PriceLog storage pricelogs = priceLog[oracles.oracleAddress];
                sumPrice = addUnderFlow(sumPrice, divUnderFlow(mulUnderFlow(subUnderFlow(oracles.lastPrice, pricelogs.lastUpdatedPrice), 100000), oracles.lastPrice));
                if(pricelog.lastUpdatedPrice == 0) {
                    sumPrice = 0;
                }
                pricelog.lastUpdatedPrice = oracles.lastPrice;
                activeOracle = activeOracle.add(1);
            }
        }

        int256 avgMovement = divUnderFlow(sumPrice, int256(activeOracle));
        if(averageLog.referenceRate == 0) {
            averageLog.referenceRate = decimals;
        }
        int256 refRate = divUnderFlow(mulUnderFlow(averageLog.referenceRate, addUnderFlow(decimals, divUnderFlow(mulUnderFlow(decimals, avgMovement), 10000000))), decimals);

        averageLog.averageMovement = avgMovement;
        averageLog.referenceRate = refRate;

        return uint256(refRate);
    }

    /**
     * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
     *
     * @dev The supply adjustment equals (_totalSupply * DeviationFromTargetRate) / rebaseLag
     *      Where DeviationFromTargetRate is (MarketOracleRate - targetRate) / targetRate
     *      and targetRate is 1
     */
    function rebase() external onlyOrchestrator {
        require(inRebaseWindow(), 'Must be in the rebase window');

        // This comparison also ensures there is no reentrancy.
        require(lastRebaseTimestampSec.add(minRebaseTimeIntervalSec) < now, 'Not allowed to rebase so soon since the last rebase');

        // Snap the rebase time to the start of this window.
        lastRebaseTimestampSec = now.sub(
            now.mod(minRebaseTimeIntervalSec)).add(rebaseWindowOffsetSec);

        epoch = epoch.add(1);

        uint256 targetRate = TARGET_RATE;

        uint256 exchangeRate;
        bool rateValid;
        (exchangeRate, rateValid) = marketOracle.getData();
        require(rateValid, 'Rate is not valid');

        if (exchangeRate > MAX_RATE) {
            exchangeRate = MAX_RATE;
        }

        int256 supplyDelta = computeSupplyDelta(exchangeRate, targetRate);

        // Apply the Dampening factor.
        supplyDelta = supplyDelta.div(rebaseLag.toInt256Safe());

        if (supplyDelta > 0 && oms.totalSupply().add(uint256(supplyDelta)) > MAX_SUPPLY) {
            supplyDelta = (MAX_SUPPLY.sub(oms.totalSupply())).toInt256Safe();
        }

        uint256 supplyAfterRebase = oms.rebase(epoch, supplyDelta);

        marketOracle.sync();

        assert(supplyAfterRebase <= MAX_SUPPLY);
        emit LogRebase(epoch, exchangeRate, supplyDelta, now);
    }

    /**
     * @notice Sets the reference to the market oracle.
     * @param marketOracle_ The address of the market oracle contract.
     */
    function setMarketOracle(IOracle marketOracle_)
        external
        onlyOwner
    {
        require(marketOracle_ != address(0), 'The address can not be a zero-address');
        marketOracle = marketOracle_;
    }

    /**
     * @notice Sets the reference to the orchestrator.
     * @param orchestrator_ The address of the orchestrator contract.
     */
    function setOrchestrator(address orchestrator_)
        external
        onlyOwner
    {
        require(orchestrator_ != address(0), 'The address can not be a zero-address');
        orchestrator = orchestrator_;
    }

    /**
     * @notice Sets the deviation threshold fraction. If the exchange rate given by the market
     *         oracle is within this fractional distance from the targetRate, then no supply
     *         modifications are made. DECIMALS fixed point number.
     * @param deviationThreshold_ The new exchange rate threshold fraction.
     */
    function setDeviationThreshold(uint256 deviationThreshold_)
        external
        onlyOwner
    {
        deviationThreshold = deviationThreshold_;
    }

    /**
     * @notice Sets the rebase lag parameter.
               It is used to dampen the applied supply adjustment by 1 / rebaseLag
               If the rebase lag R, equals 1, the smallest value for R, then the full supply
               correction is applied on each rebase cycle.
               If it is greater than 1, then a correction of 1/R of is applied on each rebase.
     * @param rebaseLag_ The new rebase lag parameter.
     */
    function setRebaseLag(uint256 rebaseLag_)
        external
        onlyOwner
    {
        require(rebaseLag_ > 0, 'Rebase lag must be greater than 0');
        rebaseLag = rebaseLag_;
    }

    /**
     * @notice Sets the parameters which control the timing and frequency of
     *         rebase operations.
     *         a) the minimum time period that must elapse between rebase cycles.
     *         b) the rebase window offset parameter.
     *         c) the rebase window length parameter.
     * @param minRebaseTimeIntervalSec_ More than this much time must pass between rebase
     *        operations, in seconds.
     * @param rebaseWindowOffsetSec_ The number of seconds from the beginning of
              the rebase interval, where the rebase window begins.
     * @param rebaseWindowLengthSec_ The length of the rebase window in seconds.
     */
    function setRebaseTimingParameters(
        uint256 minRebaseTimeIntervalSec_,
        uint256 rebaseWindowOffsetSec_,
        uint256 rebaseWindowLengthSec_)
        external
        onlyOwner
    {
        require(minRebaseTimeIntervalSec_ > 0, 'Min rebase time interval must be greater than 0');
        require(rebaseWindowOffsetSec_ < minRebaseTimeIntervalSec_, 'Rebase window offset must be less than min rebase time interval');

        minRebaseTimeIntervalSec = minRebaseTimeIntervalSec_;
        rebaseWindowOffsetSec = rebaseWindowOffsetSec_;
        rebaseWindowLengthSec = rebaseWindowLengthSec_;
    }

    /**
     * @dev ZOS upgradable contract initialization method.
     *      It is called at the time of contract creation to invoke parent class initializers and
     *      initialize the contract's state variables.
     */
    function initialize(address owner_, Oms oms_)
        public
        initializer
    {
        require(owner_ != address(0), 'The address can not be a zero-address');
        Ownable.initialize(owner_);

        // deviationThreshold = 0.05e18 = 5e16
        deviationThreshold = 5 * 10 ** (DECIMALS-2);

        // rebaseLag = 30;
        rebaseLag = 10;
        minRebaseTimeIntervalSec = 1 days;
        rebaseWindowOffsetSec = 39600;  // 11AM UTC
        rebaseWindowLengthSec = 30 minutes;

        oms = oms_;
    }

    /**
     * @return If the latest block timestamp is within the rebase time window it, returns true.
     *         Otherwise, returns false.
     */
    function inRebaseWindow() public view returns (bool) {
        return (
            now.mod(minRebaseTimeIntervalSec) >= rebaseWindowOffsetSec &&
            now.mod(minRebaseTimeIntervalSec) < (rebaseWindowOffsetSec.add(rebaseWindowLengthSec))
        );
    }

    /**
     * @return Computes the total supply adjustment in response to the exchange rate
     *         and the targetRate.
     */
    function computeSupplyDelta(uint256 rate, uint256 targetRate)
        private
        view
        returns (int256)
    {
        if (withinDeviationThreshold(rate, targetRate)) {
            return 0;
        }

        // supplyDelta = totalSupply * (rate - targetRate) / targetRate
        int256 targetRateSigned = targetRate.toInt256Safe();
        return oms.totalSupply().toInt256Safe()
            .mul(rate.toInt256Safe().sub(targetRateSigned))
            .div(targetRateSigned);
    }

    /**
     * @param rate The current exchange rate, an 18 decimal fixed point number.
     * @param targetRate The target exchange rate, an 18 decimal fixed point number.
     * @return If the rate is within the deviation threshold from the target rate, returns true.
     *         Otherwise, returns false.
     */
    function withinDeviationThreshold(uint256 rate, uint256 targetRate)
        private
        view
        returns (bool)
    {
        uint256 absoluteDeviationThreshold = targetRate.mul(deviationThreshold)
            .div(10 ** DECIMALS);

        return (rate >= targetRate && rate.sub(targetRate) < absoluteDeviationThreshold)
            || (rate < targetRate && targetRate.sub(rate) < absoluteDeviationThreshold);
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