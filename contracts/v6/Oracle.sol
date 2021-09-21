pragma solidity =0.6.6;

import "./library/SafeMath.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/IUniswapV2Factory.sol";
import "./library/FullMath.sol";
import "./library/Babylonian.sol";
import "./library/BitMath.sol";
import "./library/FixedPoint.sol";
import "./library/UniswapV2OracleLibrary.sol";
import "./library/UniswapV2Library.sol";

contract Oracle {
    using SafeMath for uint;
    using FixedPoint for *;

    event SyncOracle(IUniswapV2Pair indexed _pair, uint32 _blockTimestampLast);

    uint public constant PERIOD = 23 hours;

    IUniswapV2Pair immutable pair;
    address public immutable token0;
    address public immutable token1;
    address internal usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint    public price0CumulativeLast;
    uint    public price1CumulativeLast;
    uint32  public blockTimestampLast;
    uint256 public tokenPrice;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor(address factory, address tokenA, address tokenB) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'OraclePrice: NO_RESERVES'); // ensure that there's liquidity in the pair
    }

    function update() internal {
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, 'OraclePrice: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }
    
    function getData() external returns (uint amountOut, bool status) {
        update();
        
        if (token0 != usdc) {
            amountOut = price0Average.mul(10**18).decode144();
            amountOut = amountOut.mul(10**12);
        } else {
            require(token1 != usdc, 'OraclePrice: INVALID_TOKEN');
            amountOut = price1Average.mul(10**18).decode144();
            amountOut = amountOut.mul(10**12);
        }
        
        tokenPrice = amountOut;
        status = true;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, 'OraclePrice: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }

    // Synchronise the price data on the uniswap pair contract
    function sync() external {
        pair.sync();
        emit SyncOracle(pair, blockTimestampLast);
    }
}