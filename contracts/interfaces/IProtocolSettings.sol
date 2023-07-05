// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IProtocolSettings {

  /* ============ VIEWS =========== */

  function redemptionFeeWithUSBTokens() external view returns (uint256);

  function redemptionFeeWithXTokens() external view returns (uint256);


  /* ============ MUTATIVE FUNCTIONS =========== */

  function setRedemptionFeeWithUSBTokens(uint256 newRedemptionFeeWithUSBTokens) external;

  function setRedemptionFeeWithXTokens(uint256 newRedemptionFeeWithXTokens) external;

}