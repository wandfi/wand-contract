// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "../libs/Constants.sol";

interface IInterestPoolFactory {

  function stakingTokens() external view returns (address[] memory);

  function poolExists(address stakingToken) external view returns (bool);

  function getInterestPoolAddress(address stakingToken) external view returns (address);

  function addInterestPool(address stakingToken, Constants.InterestPoolStakingTokenType stakingTokenType, address swapPool, uint256 swapPoolCoinsCount, address[] memory rewardTokens) external;

  function addRewardToken(address stakingToken, address rewardToken) external;

  function addRewardTokenToAllPools(address rewardToken) external;

  function distributeInterestRewards(address rewardToken, uint256 totalAmount) external returns (bool);

}