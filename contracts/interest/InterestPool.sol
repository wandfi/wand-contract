// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IInterestPool.sol";
import "../libs/Constants.sol";

abstract contract InterestPool is IInterestPool, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  address public immutable wandProtocol;
  address public immutable interestPoolFactory;
  address public immutable stakingToken;
  Constants.InterestPoolStakingTokenInfo internal _stakingTokenInfo;

  EnumerableSet.AddressSet internal _rewardTokensSet;

  uint256 internal _totalStakingAmount;
  mapping(address => uint256) internal _userStakingAmount;

  // Reward token => Amount
  mapping(address => uint256) public stakingRewardsPerToken;
  // Reward token => User => Amount
  mapping(address => mapping(address => uint256)) public userStakingRewardsPerTokenPaid;
  // Reward token => User => Amount
  mapping(address => mapping(address => uint256)) public userStakingRewards;
  
  constructor(
    address _wandProtocol,
    address _interestPoolFactory,
    address _stakingToken,
    address[] memory _rewardTokens
  ) {
    require(_wandProtocol != address(0), "Zero address detected");
    require(_interestPoolFactory != address(0), "Zero address detected");
    require(_stakingToken != address(0), "Zero address detected");
    require(_rewardTokens.length > 0, "No reward tokens");

    wandProtocol = _wandProtocol;
    interestPoolFactory = _interestPoolFactory;

    stakingToken = _stakingToken;

    for (uint256 i = 0; i < _rewardTokens.length; i++) {
      _addRewardToken(_rewardTokens[i]);
    }
  }

  /* ========== VIEWS ========== */

  function totalStakingAmount() external view returns (uint256) {
    return _totalStakingAmount;
  }

  function userStakingAmount(address account) external view returns (uint256) {
    return _userStakingAmount[account];
  }

  function stakingRewardsEarned(address rewardToken, address account) public view onlyValidRewardToken(rewardToken) returns (uint256) {
    return
      _userStakingAmount[account]
        .mul(stakingRewardsPerToken[rewardToken].sub(userStakingRewardsPerTokenPaid[rewardToken][account]))
        .div(1e18)
        .add(userStakingRewards[rewardToken][account]);
  }

  function rewardTokenAdded(address rewardToken) public view returns (bool) {
    return _rewardTokensSet.contains(rewardToken);
  }

  function stakingTokenInfo() public view returns (Constants.InterestPoolStakingTokenInfo memory) {
    return _stakingTokenInfo;
  }

  function totalStakingAmountInUSB() public virtual view returns (uint256);

  /**
   * @dev No guarantees are made on the ordering
   */
  function rewardTokens() public view returns (address[] memory) {
    return _rewardTokensSet.values();
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function stake(uint256 amount) public nonReentrant updateAllStakingRewards(_msgSender()) {
    require(amount > 0, "Cannot stake 0 tokens");

    _totalStakingAmount = _totalStakingAmount.add(amount);
    _userStakingAmount[_msgSender()] = _userStakingAmount[_msgSender()].add(amount);

    IERC20(stakingToken).safeTransferFrom(_msgSender(), address(this), amount);

    emit Staked(_msgSender(), amount);
  }

  function unstake(uint256 amount) public nonReentrant updateAllStakingRewards(_msgSender()) {
    require(amount > 0, "Cannot unstake 0 tokens");

    _totalStakingAmount = _totalStakingAmount.sub(amount);
    _userStakingAmount[_msgSender()] = _userStakingAmount[_msgSender()].sub(amount);

    IERC20(stakingToken).safeTransfer(_msgSender(), amount);

    emit Unstaked(_msgSender(), amount);
  }

  function getStakingRewards(address rewardToken) public nonReentrant updateStakingRewards(rewardToken, _msgSender()) onlyValidRewardToken(rewardToken) {
    uint256 reward = userStakingRewards[rewardToken][_msgSender()];

    if (reward > 0) {
      userStakingRewards[rewardToken][_msgSender()] = 0;
      IERC20(rewardToken).safeTransfer(_msgSender(), reward);
      emit StakingRewardsPaid(rewardToken, _msgSender(), reward);
    }
  }

  function getAllStakingRewards() external {
    for (uint256 i = 0; i < _rewardTokensSet.length(); i++) {
      address rewardToken = _rewardTokensSet.at(i);
      getStakingRewards(rewardToken);
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function addRewardToken(address rewardToken) public nonReentrant onlyInterestPoolFactory {
    _addRewardToken(rewardToken);
  }

  function _addRewardToken(address rewardToken) internal {
    require(rewardToken != address(0), "Zero address detected");
    require(!_rewardTokensSet.contains(rewardToken), "Reward token already added");
    _rewardTokensSet.add(rewardToken);
    emit RewardTokenAdded(rewardToken);
  }

  function notifyRewardsAdded(address rewardToken, uint256 amount) external nonReentrant updateStakingRewards(rewardToken, address(0)) onlyValidRewardToken(rewardToken) onlyInterestPoolFactory {
    require(amount > 0, "Reward amount should be greater than 0");
    require(_totalStakingAmount > 0, "No staking yet");

    stakingRewardsPerToken[rewardToken] = stakingRewardsPerToken[rewardToken].add(amount.mul(1e18).div(_totalStakingAmount));

    emit StakingRewardsAdded(rewardToken, amount);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyInterestPoolFactory() {
    require(_msgSender() == interestPoolFactory, "Caller is not InterestPoolFactory");
    _;
  }

  modifier onlyValidRewardToken(address rewardToken) {
    require(_rewardTokensSet.contains(rewardToken), "Invalid reward token");
    _;
  }

  modifier updateStakingRewards(address rewardToken, address account) {
    _updateStakingRewards(rewardToken, account);
    _;
  }

  modifier updateAllStakingRewards(address account) {
    for (uint256 i = 0; i < _rewardTokensSet.length(); i++) {
      address rewardToken = _rewardTokensSet.at(i);
      _updateStakingRewards(rewardToken, account);
    }
    _;
  }

  function _updateStakingRewards(address rewardToken, address account) internal {
    require(_rewardTokensSet.contains(rewardToken), "Invalid reward token");

    if (account != address(0)) {
      userStakingRewards[rewardToken][account] = stakingRewardsEarned(rewardToken, account);
      userStakingRewardsPerTokenPaid[rewardToken][account] = stakingRewardsPerToken[rewardToken];
    }
  }

  /* ========== EVENTS ========== */

  event RewardTokenAdded(address indexed rewardToken);
  event StakingRewardsAdded(address indexed rewardToken, uint256 rewardAmount);

  event Staked(address indexed user, uint256 amount);
  event Unstaked(address indexed user, uint256 amount);
  event StakingRewardsPaid(address indexed rewardToken, address indexed user, uint256 reward);
}