// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";
import "../interfaces/IUsb.sol";
import "../interfaces/IVault.sol";

contract PtyPool is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */
  
  Constants.PtyPoolType public immutable poolType;
  IVault internal immutable _vault;

  address internal _stakingToken;
  address internal _targetToken;
  address internal _stakingYieldsToken;
  address internal _matchingYieldsToken;

  uint256 internal _totalStakingShares;
  mapping(address => uint256) internal _userStakingShares;

  // For MintUsbAboveAARU only.
  uint256 internal _totalStakingAssetBalance;

  uint256 internal _stakingYieldsPerShare;
  mapping(address => uint256) internal _userStakingYieldsPerSharePaid;
  mapping(address => uint256) internal _userStakingYields;

  uint256 internal _accruedMatchingYields;
  uint256 internal _matchingYieldsPerShare;
  // For MintUsbAboveAARU pools, matching yields is paid in USB shares (since it's rebasable token)
  mapping(address => uint256) internal _userMatchingYieldsPerSharePaid;
  mapping(address => uint256) internal _userMatchingYields;
  
  uint256 internal _targetTokensPerShare;
  mapping(address => uint256) internal _userTargetTokenSharesPerSharePaid;
  mapping(address => uint256) internal _userTargetTokenShares;

  // [[Δtimestamp,stakeYields]]
  uint256[2][] internal _recentStakeYields;
  uint256 internal _lastAddStakeYieldsTime;
  
  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _vault_,
    Constants.PtyPoolType _poolType,
    address _stakingYieldsToken_,
    address _matchingYieldsToken_
  ) Ownable() {
    _vault = IVault(_vault_);
    poolType = _poolType;
    if (poolType == Constants.PtyPoolType.RedeemByUsbBelowAARS) {
      _stakingToken = _vault.usbToken();
      _targetToken = _vault.assetToken();
    } else if (poolType == Constants.PtyPoolType.MintUsbAboveAARU) {
      _stakingToken = _vault.assetToken();
      _targetToken = _vault.usbToken();
    } else {
      revert("Unsupported PtyPoolType");
    }

    _stakingYieldsToken = _stakingYieldsToken_;
    _matchingYieldsToken = _matchingYieldsToken_;
    _lastAddStakeYieldsTime = block.timestamp;
  }

  receive() external payable {}

  /* ========== VIEWS ========== */

  function vault() public view returns (address) {
    return address(_vault);
  }

  function stakingToken() public view returns (address) {
    return _stakingToken;
  }

  function targetToken() public view returns (address) {
    return _targetToken;
  }

  function stakingYieldsToken() public view returns (address) {
    return _stakingYieldsToken;
  }

  function machingYieldsToken() public view returns (address) {
    return _matchingYieldsToken;
  }

  function totalStakingShares() public view returns (uint256) {
    return _totalStakingShares;
  }

  function totalStakingBalance() public view returns (uint256) {
    require(poolType == Constants.PtyPoolType.RedeemByUsbBelowAARS || poolType == Constants.PtyPoolType.MintUsbAboveAARU, "Unsupported PtyPoolType");
    
    if (poolType == Constants.PtyPoolType.RedeemByUsbBelowAARS) {
      require(_stakingToken == _vault.usbToken(), "Staking token should be USB");
      return IERC20(_stakingToken).balanceOf(address(this));
    }
    else {
      return _totalStakingAssetBalance;
    }
  }

  function userStakingShares(address account) public view returns (uint256) {
    return _userStakingShares[account];
  }

  function userStakingBalance(address account) public view returns (uint256) {
    return getStakingBalanceByShares(_userStakingShares[account]);
  }

  function earnedStakingYields(address account) public view returns (uint256) {
    return _userStakingShares[account].mul(_stakingYieldsPerShare.sub(_userStakingYieldsPerSharePaid[account])).div(1e18).add(_userStakingYields[account]);
  }

  function earnedMatchingYields(address account) public view returns (uint256) {
    return _userStakingShares[account].mul(_matchingYieldsPerShare.sub(_userMatchingYieldsPerSharePaid[account])).div(1e18).add(_userMatchingYields[account]);
  }

  function earnedMatchedToken(address account) public view returns (uint256) {
    return _userStakingShares[account].mul(_targetTokensPerShare.sub(_userTargetTokenSharesPerSharePaid[account])).div(1e18).add(_userTargetTokenShares[account]);
  }

  function getStakingSharesByBalance(uint256 stakingBalance) public view returns (uint256) {
    if (totalStakingBalance() == 0) return stakingBalance;

    return stakingBalance
      .mul(_totalStakingShares)
      .div(totalStakingBalance());
  }

  function getStakingBalanceByShares(uint256 stakingShares) public view returns (uint256) {
    if (_totalStakingShares == 0) return 0;
  
    return stakingShares
      .mul(totalStakingBalance())
      .div(_totalStakingShares);
  }

  function getRecentStakeYields() public view returns(uint256[2][] memory){
    return _recentStakeYields;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function stake(uint256 amount) external payable nonReentrant 
    updateStakingYields(_msgSender()) updateMatchingYields(_msgSender()) updateTargetTokens(_msgSender()) {

    require(amount > 0, "Cannot stake 0");

    uint256 sharesAmount = getStakingSharesByBalance(amount);
    _totalStakingShares = _totalStakingShares.add(sharesAmount);
    _userStakingShares[_msgSender()] = _userStakingShares[_msgSender()].add(sharesAmount);

    if (poolType == Constants.PtyPoolType.MintUsbAboveAARU) {
      _totalStakingAssetBalance = _totalStakingAssetBalance.add(amount);
    }

    TokensTransfer.transferTokens(_stakingToken, _msgSender(), address(this), amount);
    emit Staked(_msgSender(), amount);
  }

  function withdraw(uint256 amount) public nonReentrant
    updateStakingYields(_msgSender()) updateMatchingYields(_msgSender()) updateTargetTokens(_msgSender()) {

    require(amount > 0, "Cannot withdraw 0");
    require(amount <= userStakingBalance(_msgSender()), "Insufficient balance");

    uint256 sharesAmount = getStakingSharesByBalance(amount);
    _totalStakingShares = _totalStakingShares.sub(sharesAmount);
    _userStakingShares[_msgSender()] = _userStakingShares[_msgSender()].sub(sharesAmount);
    if (poolType == Constants.PtyPoolType.MintUsbAboveAARU) {
      _totalStakingAssetBalance = _totalStakingAssetBalance.sub(amount);
    }

    TokensTransfer.transferTokens(_stakingToken, address(this), _msgSender(), amount);
    emit Withdrawn(_msgSender(), amount);
  }

  function getStakingYields() public nonReentrant updateStakingYields(_msgSender()) {
    uint256 userYields = _userStakingYields[_msgSender()];
    if (userYields > 0) {
      _userStakingYields[_msgSender()] = 0;
      TokensTransfer.transferTokens(_stakingYieldsToken, address(this), _msgSender(), userYields);
      emit StakingYieldsPaid(_msgSender(), userYields);
    }
  }

  function getMatchingYields() public nonReentrant updateMatchingYields(_msgSender()) {
    uint256 userYields = _userMatchingYields[_msgSender()];
    if (userYields > 0) {
      _userMatchingYields[_msgSender()] = 0;
      TokensTransfer.transferTokens(_matchingYieldsToken, address(this), _msgSender(), userYields);
      emit MatchingYieldsPaid(_msgSender(), userYields);
    }
  }

  function getMatchingOutTokens() public nonReentrant updateTargetTokens(_msgSender()) {
    uint256 userYields = _userTargetTokenShares[_msgSender()];
    if (userYields > 0) {
      _userTargetTokenShares[_msgSender()] = 0;
      TokensTransfer.transferTokens(_targetToken, address(this), _msgSender(), userYields);
      emit MatchedTokenPaid(_msgSender(), userYields);
    }
  }

  /**
   * @notice Useful for Pty Pools Below AARS, since matching out tokens and yields tokens are all asset tokens.
   */
  function getMatchingTokensAndYields() external {
    getMatchingOutTokens();
    getMatchingYields();
  }

  function claimAll() external {
    getMatchingOutTokens();
    getMatchingYields();
    getStakingYields();
  }

  function exit() external {
    withdraw(userStakingBalance(_msgSender()));
    getStakingYields();
    getMatchingYields();
    getMatchingOutTokens();
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function addStakingYields(uint256 yieldsAmount) external payable nonReentrant updateStakingYields(address(0)) onlyVault {
    require(yieldsAmount > 0, "Too small yields amount");
    require(_totalStakingShares > 0, "No user stakes");

    if(_recentStakeYields.length > 5){
      for (uint i = 0; i < 5; i++) {
        _recentStakeYields[i] = _recentStakeYields[i + 1];
      }
      _recentStakeYields.pop();
    }
    _recentStakeYields.push([block.timestamp - _lastAddStakeYieldsTime, yieldsAmount]);
    _lastAddStakeYieldsTime = block.timestamp;

    _stakingYieldsPerShare = _stakingYieldsPerShare.add(yieldsAmount.mul(1e18).div(_totalStakingShares));
    emit StakingYieldsAdded(yieldsAmount);
  }

  function addMatchingYields(uint256 yieldsAmount) external nonReentrant updateMatchingYields(address(0)) onlyVault {
    require(yieldsAmount > 0, "Too small yields amount");
    require(_totalStakingShares > 0, "No user stakes");
    _accruedMatchingYields = _accruedMatchingYields.add(yieldsAmount);
    emit MatchingYieldsAdded(yieldsAmount);
  }

  function notifyMatchedBelowAARS(uint256 assetAmountAdded) external nonReentrant updateTargetTokens(address(0)) onlyVault {
    require(poolType == Constants.PtyPoolType.RedeemByUsbBelowAARS, "Invalid pool type");
    require(_vault.vaultPhase() == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    _targetTokensPerShare = _targetTokensPerShare.add(assetAmountAdded.mul(1e18).div(_totalStakingShares));
    emit MatchedTokensAdded(assetAmountAdded);

    if (_accruedMatchingYields > 0) {
      _matchingYieldsPerShare = _matchingYieldsPerShare.add(_accruedMatchingYields.mul(1e18).div(_totalStakingShares));
      _accruedMatchingYields = 0;
    }
  }

  function notifyMatchedAboveAARU(uint256 assetAmountMatched, uint256 usbSharesReceived) external nonReentrant updateTargetTokens(address(0)) onlyVault {
    require(poolType == Constants.PtyPoolType.MintUsbAboveAARU, "Invalid pool type");
    require(_vault.vaultPhase() == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    _totalStakingAssetBalance = _totalStakingAssetBalance.sub(assetAmountMatched);
    TokensTransfer.transferTokens(_stakingToken, address(this), _msgSender(), assetAmountMatched);

    _targetTokensPerShare = _targetTokensPerShare.add(usbSharesReceived.mul(1e18).div(_totalStakingShares));
    emit MatchedTokensAdded(usbSharesReceived);

    if (_accruedMatchingYields > 0) {
      _matchingYieldsPerShare = _matchingYieldsPerShare.add(_accruedMatchingYields.mul(1e18).div(_totalStakingShares));
      _accruedMatchingYields = 0;
    }
  }


  /* ========== MODIFIERS ========== */

  modifier onlyVault() {
    require(_msgSender() == address(_vault), "Caller is not Vault");
    _;
  }

  modifier updateStakingYields(address account) {
    if (account != address(0)) {
      _userStakingYields[account] = earnedStakingYields(account);
      _userStakingYieldsPerSharePaid[account] = _stakingYieldsPerShare;
    }
    _;
  }

  modifier updateMatchingYields(address account) {
    if (account != address(0)) {
      _userMatchingYields[account] = earnedMatchingYields(account);
      _userMatchingYieldsPerSharePaid[account] = _matchingYieldsPerShare;
    }
    _;
  }

  modifier updateTargetTokens(address account) {
    if (account != address(0)) {
      _userTargetTokenShares[account] = earnedMatchedToken(account);
      _userTargetTokenSharesPerSharePaid[account] = _targetTokensPerShare;
    }
    _;
  }

  /* ========== EVENTS ========== */

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);

  event StakingYieldsAdded(uint256 yields);
  event MatchingYieldsAdded(uint256 yields);
  event MatchedTokensAdded(uint256 amount);

  event StakingYieldsPaid(address indexed user, uint256 yields);
  event MatchingYieldsPaid(address indexed user, uint256 yields);
  event MatchedTokenPaid(address indexed user, uint256 amount);
}