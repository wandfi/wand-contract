// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IProtocolSettings {

  /* ============ VIEWS =========== */

  function settingDecimals() external view returns (uint256);

  function defaultRedemptionFeeWithUSBTokens() external view returns (uint256);

  function defaultRedemptionFeeWithXTokens() external view returns (uint256);

  function assertRedemptionFeeWithUSBTokens(uint256 redemptionFeeWithUSBTokens) external view;

  function assertRedemptionFeeWithXTokens(uint256 redemptionFeeWithXTokens) external view;

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setDefaultRedemptionFeeWithUSBTokens(uint256 newRedemptionFeeWithUSBTokens) external;

  function setDefaultRedemptionFeeWithXTokens(uint256 newRedemptionFeeWithXTokens) external;

}