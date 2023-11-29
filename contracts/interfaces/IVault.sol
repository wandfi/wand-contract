// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";

interface IVault {

  function AARDecimals() external pure returns (uint256);

  function usbToken() external view returns (address);

  function assetToken() external view returns (address);

  function assetTokenPriceFeed() external view returns (address);

  function assetTokenPrice() external view returns (uint256, uint256);

  function assetTotalAmount() external view returns (uint256);

  function usbTotalSupply() external view returns (uint256);

  function leveragedToken() external view returns (address);

  function vaultPhase() external view returns (Constants.VaultPhase);

  function vaultState() external view returns (Constants.VaultState memory);

  function getParamValue(bytes32 param) external view returns (uint256);

  function AARBelowSafeLineTime() external view returns (uint256);

  function AARBelowCircuitBreakerLineTime() external view returns (uint256);
  
}