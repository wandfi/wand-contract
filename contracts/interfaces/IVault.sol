// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";

interface IVault {

  function usbToken() external view returns (address);

  function usbTotalSupply() external view returns (uint256);

  function usbTotalShares() external view returns (uint256);

  function assetTotalAmount() external view returns (uint256);

  function assetToken() external view returns (address);

  function assetTokenPrice() external view returns (uint256, uint256);

  function leveragedToken() external view returns (address);

  function getParamValue(bytes32 param) external view returns (uint256);

  function vaultPhase() external view returns (Constants.VaultPhase);

  function vaultState() external view returns (Constants.VaultState memory);

  function AAR() external view returns (uint256);

  function AARDecimals() external view returns (uint256);
}