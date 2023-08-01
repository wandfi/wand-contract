// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";

interface IInterestPoolFactory {

  function stakingTokens() external view returns (address[] memory);

  function poolExists(address stakingToken) external view returns (bool);

  function getInterestPoolAddress(address stakingToken) external view returns (address);

  function addRewardToken(address stakingToken, address rewardToken) external;

  function addRewardTokenToAllPools(address rewardToken) external;

  function distributeInterestRewards(address rewardToken, uint256 totalAmount) external returns (bool);

}