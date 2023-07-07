// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IAssetPool {

  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() external view returns (uint256);

  /**
   * @notice Current adequency ratio of the pool, with 18 decimals
   */
  function AAR() external view returns (uint256);

  function AARDecimals() external view returns (uint256);

  function setC1(uint256 newC1) external;

  function setC2(uint256 newC2) external;

  function setY(uint256 newY) external;
  
  function mintUSB(uint256 assetAmount) external payable;

  function mintXTokens(uint256 assetAmount) external payable;

  function redeemByUSB(uint256 usbAmount) external;

  function redeemByXTokens(uint256 xTokenAmount) external;

  function interestSettlement() external;

}