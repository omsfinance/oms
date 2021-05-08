pragma solidity 0.4.24;

import "./library/SafeMath.sol";
import "./library/SafeMathInt.sol";
import "./interface/IERC20.sol";
import "./common/Initializable.sol";
import "./common/Ownable.sol";
import "./common/ERC20Detailed.sol";

contract Oms is ERC20Detailed, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    event LogRebase(uint256 indexed epoch, uint256 totalSupply);
    event LogRebasePaused(bool paused);
    event LogTokenPaused(bool paused);
    event LogOmsPolicyUpdated(address omsPolicy);

    // Used for authentication
    address public omsPolicy;

    modifier onlyOmsPolicy() {
        require(msg.sender == omsPolicy, 'Only Oms Policy can call this function');
        _;
    }

    // Precautionary emergency controls.
    bool public rebasePaused;
    bool public tokenPaused;

    modifier whenRebaseNotPaused() {
        require(!rebasePaused, 'Rebase can not be paused');
        _;
    }

    modifier whenTokenNotPaused() {
        require(!tokenPaused, 'Token can not be paused');
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0), 'The address can not be a zero-address');
        require(to != address(this), 'The address can not be an instance of this contract');
        _;
    }

    uint256 private constant DECIMALS = 18;
    uint256 public constant MAX_UINT256 = ~uint256(0);
    uint256 private constant INITIAL_OMS_SUPPLY = 5000000 * 10**DECIMALS;

    // TOTAL_GONS is a multiple of INITIAL_OMS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 public constant TOTAL_GONS = MAX_UINT256 -
        (MAX_UINT256 % INITIAL_OMS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1

    uint256 private _totalSupply;
    uint256 public _gonsPerFragment;
    mapping(address => uint256) public _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedOmss;

    /**
        * @param omsPolicy_ The address of the oms policy contract to use for authentication.
        */
    function setOmsPolicy(address omsPolicy_) external onlyOwner {
        require(omsPolicy_ != address(0), 'The address can not be a zero-address');
        omsPolicy = omsPolicy_;
        emit LogOmsPolicyUpdated(omsPolicy_);
    }

    /**
        * @dev Pauses or unpauses the execution of rebase operations.
        * @param paused Pauses rebase operations if this is true.
        */
    function setRebasePaused(bool paused) external onlyOwner {
        rebasePaused = paused;
        emit LogRebasePaused(paused);
    }

    /**
        * @dev Pauses or unpauses execution of ERC-20 transactions.
        * @param paused Pauses ERC-20 transactions if this is true.
        */
    function setTokenPaused(bool paused) external onlyOwner {
        tokenPaused = paused;
        emit LogTokenPaused(paused);
    }

    /**
        * @dev Notifies Omss contract about a new rebase cycle.
        * @param supplyDelta The number of new oms tokens to add into circulation via expansion.
        * @return The total number of omss after the supply adjustment.
        */
    function rebase(uint256 epoch, int256 supplyDelta)
        external
        onlyOmsPolicy
        whenRebaseNotPaused
        returns (uint256)
    {
        if (supplyDelta == 0) {
            emit LogRebase(epoch, _totalSupply);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(supplyDelta.abs()));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        // From this point forward, _gonsPerFragment is taken as the source of truth.
        // We recalculate a new _totalSupply to be in agreement with the _gonsPerFragment
        // conversion rate.
        // This means our applied supplyDelta can deviate from the requested supplyDelta,
        // but this deviation is guaranteed to be < (_totalSupply^2)/(TOTAL_GONS - _totalSupply).
        //
        // In the case of _totalSupply <= MAX_UINT128 (our current supply cap), this
        // deviation is guaranteed to be < 1, so we can omit this step. If the supply cap is
        // ever increased, it must be re-included.
        // _totalSupply = TOTAL_GONS.div(_gonsPerFragment)

        emit LogRebase(epoch, _totalSupply);
        return _totalSupply;
    }

    function initialize(address owner_) public initializer {
        require(owner_ != address(0), 'The address can not be a zero-address');
        
        ERC20Detailed.initialize("Oms", "OMS", uint8(DECIMALS));
        Ownable.initialize(owner_);

        _totalSupply = INITIAL_OMS_SUPPLY;
        _gonBalances[owner_] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit Transfer(address(0x0), owner_, _totalSupply);
    }

    /**
        * @return The total number of omss.
        */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
        * @param who The address to query.
        * @return The balance of the specified address.
        */
    function balanceOf(address who) public view returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    /**
        * @dev Transfer tokens to a specified address.
        * @param to The address to transfer to.
        * @param value The amount to be transferred.
        * @return True on success, false otherwise.
        */
    function transfer(address to, uint256 value)
        public
        validRecipient(to)
        whenTokenNotPaused
        returns (bool)
    {
        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
        * @dev Function to check the amount of tokens that an owner has allowed to a spender.
        * @param owner_ The address which owns the funds.
        * @param spender The address which will spend the funds.
        * @return The number of tokens still available for the spender.
        */
    function allowance(address owner_, address spender)
        public
        view
        returns (uint256)
    {
        return _allowedOmss[owner_][spender];
    }

    /**
        * @dev Transfer tokens from one address to another.
        * @param from The address you want to send tokens from.
        * @param to The address you want to transfer to.
        * @param value The amount of tokens to be transferred.
        */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public validRecipient(to) whenTokenNotPaused returns (bool) {
        _allowedOmss[from][msg.sender] = _allowedOmss[from][msg
            .sender]
            .sub(value);

        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        emit Transfer(from, to, value);

        return true;
    }

    /**
        * @dev Approve the passed address to spend the specified amount of tokens on behalf of
        * msg.sender. This method is included for ERC20 compatibility.
        * increaseAllowance and decreaseAllowance should be used instead.
        * Changing an allowance with this method brings the risk that someone may transfer both
        * the old and the new allowance - if they are both greater than zero - if a transfer
        * transaction is mined before the later approve() call is mined.
        *
        * @param spender The address which will spend the funds.
        * @param value The amount of tokens to be spent.
        */
    function approve(address spender, uint256 value)
        public
        whenTokenNotPaused
        returns (bool)
    {
        _allowedOmss[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
        * @dev Increase the amount of tokens that an owner has allowed to a spender.
        * This method should be used instead of approve() to avoid the double approval vulnerability
        * described above.
        * @param spender The address which will spend the funds.
        * @param addedValue The amount of tokens to increase the allowance by.
        */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        whenTokenNotPaused
        returns (bool)
    {
        _allowedOmss[msg.sender][spender] = _allowedOmss[msg
            .sender][spender]
            .add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedOmss[msg.sender][spender]
        );
        return true;
    }

    /**
        * @dev Decrease the amount of tokens that an owner has allowed to a spender.
        *
        * @param spender The address which will spend the funds.
        * @param subtractedValue The amount of tokens to decrease the allowance by.
        */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        whenTokenNotPaused
        returns (bool)
    {
        uint256 oldValue = _allowedOmss[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedOmss[msg.sender][spender] = 0;
        } else {
            _allowedOmss[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedOmss[msg.sender][spender]
        );
        return true;
    }
}