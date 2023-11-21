// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";
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

  uint256 internal _totalStakingBalance;
  uint256 internal _totalStakingShares;
  mapping(address => uint256) internal _userStakingShares;

  uint256 internal _stakingYieldsPerShare;
  mapping(address => uint256) internal _userStakingYieldsPerSharePaid;
  mapping(address => uint256) internal _userStakingYields;

  uint256 internal _accruedMatchingYields;
  uint256 internal _matchingYieldsPerShare;
  mapping(address => uint256) internal _userMatchingYieldsPerSharePaid;
  mapping(address => uint256) internal _userMatchingYields;
  
  uint256 internal _targetTokensPerShare;
  mapping(address => uint256) internal _userTargetTokenSharesPerSharePaid;
  mapping(address => uint256) internal _userTargetTokenShares;

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
  }

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

  function totalStakingBalance() public view returns (uint256) {
    return _totalStakingBalance;
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
    if (_totalStakingBalance == 0) return stakingBalance;

    return stakingBalance
      .mul(_totalStakingShares)
      .div(_totalStakingBalance);
  }

  function getStakingBalanceByShares(uint256 stakingShares) public view returns (uint256) {
    if (_totalStakingShares == 0) return 0;
  
    return stakingShares
      .mul(_totalStakingBalance)
      .div(_totalStakingShares);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function stake(uint256 amount) external payable nonReentrant 
    updateStakingYields(_msgSender()) updateMatchingYields(_msgSender()) updateTargetTokens(_msgSender()) {

    require(amount > 0, "Cannot stake 0");

    uint256 sharesAmount = getStakingSharesByBalance(amount);
    _totalStakingShares = _totalStakingShares.add(sharesAmount);
    _userStakingShares[_msgSender()] = _userStakingShares[_msgSender()].add(sharesAmount);

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

  function getMatchingYields() public nonReentrant updateStakingYields(_msgSender()) {
    uint256 userYields = _userMatchingYields[_msgSender()];
    if (userYields > 0) {
      _userMatchingYields[_msgSender()] = 0;
      TokensTransfer.transferTokens(_matchingYieldsToken, address(this), _msgSender(), userYields);
      emit MatchingYieldsPaid(_msgSender(), userYields);
    }
  }

  function getMatchingOutTokens() public nonReentrant updateStakingYields(_msgSender()) {
    uint256 userYields = _userTargetTokenShares[_msgSender()];
    if (userYields > 0) {
      _userTargetTokenShares[_msgSender()] = 0;
      TokensTransfer.transferTokens(_targetToken, address(this), _msgSender(), userYields);
      emit MatchedTokenPaid(_msgSender(), userYields);
    }
  }

  function exit() external {
    withdraw(userStakingBalance(_msgSender()));
    getStakingYields();
    getMatchingYields();
    getMatchingOutTokens();
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function addStakingYields(uint256 yieldsAmount) external nonReentrant updateStakingYields(address(0)) onlyVault {
    require(yieldsAmount > 0, "Too small yields amount");
    require(_totalStakingShares > 0, "No user stakes");

    _stakingYieldsPerShare = _stakingYieldsPerShare.add(yieldsAmount.mul(1e18).div(_totalStakingShares));
    TokensTransfer.transferTokens(_stakingYieldsToken, _msgSender(), address(this), yieldsAmount);
    emit StakingYieldsAdded(yieldsAmount);
  }

  function addMatchingYields(uint256 yieldsAmount) external nonReentrant updateMatchingYields(address(0)) onlyVault {
    require(yieldsAmount > 0, "Too small yields amount");
    require(_totalStakingShares > 0, "No user stakes");

    _accruedMatchingYields = _accruedMatchingYields.add(yieldsAmount);
    emit MatchingYieldsAdded(yieldsAmount);
  }

  function notifyMatchedBelowAARS(uint256 assetAmountAdded) external nonReentrant onlyVault {
    require(poolType == Constants.PtyPoolType.RedeemByUsbBelowAARS, "Invalid pool type");
    require(_vault.getVaultPhase() == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    _targetTokensPerShare = _targetTokensPerShare.add(assetAmountAdded.mul(1e18).div(_totalStakingShares));
    emit MatchedTokensAdded(assetAmountAdded);

    _matchingYieldsPerShare = _matchingYieldsPerShare.add(_accruedMatchingYields.mul(1e18).div(_totalStakingShares));
    _accruedMatchingYields = 0;
  }

  function notifyMatchedAboveAARU(uint256 usbAmountAdded) external nonReentrant onlyVault {
    require(poolType == Constants.PtyPoolType.MintUsbAboveAARU, "Invalid pool type");
    require(_vault.getVaultPhase() == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

  }


  /* ========== MODIFIERS ========== */

  modifier onlyVault() {
    require(_msgSender() == address(_vault), "Caller is not _vault");
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