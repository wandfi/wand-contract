// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ProtoInterestPool is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  IERC20 public rewardsToken;
  IERC20 public stakingToken;
  uint256 public rewardPerToken;

  mapping(address => uint256) public userRewardPerTokenPaid;
  mapping(address => uint256) public userRewards;

  uint256 internal _totalSupply;
  mapping(address => uint256) private _balances;

  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _rewardsToken,
    address _stakingToken
  ) Ownable() {
    rewardsToken = IERC20(_rewardsToken);
    stakingToken = IERC20(_stakingToken);
  }

  /* ========== VIEWS ========== */

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  function earned(address account) public view returns (uint256) {
    return _balances[account].mul(rewardPerToken.sub(userRewardPerTokenPaid[account])).div(1e18).add(userRewards[account]);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function stake(uint256 amount) external virtual payable nonReentrant updateReward(msg.sender) {
    require(amount > 0, "Cannot stake 0");
    _totalSupply = _totalSupply.add(amount);
    _balances[msg.sender] = _balances[msg.sender].add(amount);
    // console.log('stake, msg.sender balance: %s', stakingToken.balanceOf(msg.sender));
    stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    emit Staked(msg.sender, amount);
  }

  function withdraw(uint256 amount) public virtual nonReentrant updateReward(msg.sender) {
    require(amount > 0, "Cannot withdraw 0");
    _totalSupply = _totalSupply.sub(amount);
    _balances[msg.sender] = _balances[msg.sender].sub(amount);
    stakingToken.safeTransfer(msg.sender, amount);
    emit Withdrawn(msg.sender, amount);
  }

  function getReward() public nonReentrant updateReward(msg.sender) {
    uint256 userReward = userRewards[msg.sender];
    if (userReward > 0) {
      userRewards[msg.sender] = 0;
      rewardsToken.safeTransfer(msg.sender, userReward);
      emit RewardPaid(msg.sender, userReward);
    }
  }

  function exit() external {
    withdraw(_balances[msg.sender]);
    getReward();
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function addRewards(uint256 rewardsAmount) external updateReward(address(0)) onlyOwner {
    require(rewardsAmount > 0, "Too small rewards amount");

    rewardsToken.safeTransferFrom(msg.sender, address(this), rewardsAmount);

    if (_totalSupply > 0) {
      rewardPerToken = rewardPerToken.add(rewardsAmount.mul(1e18).div(_totalSupply));
    }

    emit RewardAdded(rewardsAmount);
  }

  /* ========== MODIFIERS ========== */

  modifier updateReward(address account) {
    if (account != address(0)) {
      userRewards[account] = earned(account);
      userRewardPerTokenPaid[account] = rewardPerToken;
    }
    _;
  }

  /* ========== EVENTS ========== */

  event RewardAdded(uint256 reward);
  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
  event AdminRewardWithdrawn(address indexed to, uint256 amount);
}