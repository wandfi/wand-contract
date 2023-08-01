// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";

interface IInterestPool {

  function totalStakingAmount() external view returns (uint256);

  function userStakingAmount(address user) external view returns (uint256);

  function rewardTokenAdded(address rewardToken) external view returns (bool);

  function stakingTokenInfo() external view returns (Constants.InterestPoolStakingTokenInfo memory);

  function totalStakingAmountInUSB() external view returns (uint256);

  function rewardTokens() external view returns (address[] memory);

  function stakingRewardsEarned(address rewardToken, address account) external view returns (uint256);

  function stake(uint256 amount) external;

  function unstake(uint256 amount) external;

  function getStakingRewards(address rewardToken) external;

  function getAllStakingRewards() external;

  function addRewardToken(address rewardToken) external;

  function notifyRewardsAdded(address rewardToken, uint256 amount) external;

}