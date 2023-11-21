// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IPtyPool {

  function vault() external view returns (address);

  function totalStakingBalance() external view returns (uint256);

  function addStakingYields(uint256 yieldsAmount) external;

  function addMatchingYields(uint256 yieldsAmount) external;

  function notifyMatchedBelowAARS(uint256 assetAmountAdded) external;

  function notifyMatchedAboveAARU(uint256 usbAmountAdded) external;

}