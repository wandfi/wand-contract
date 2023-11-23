// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";

interface IVault {

  function usbToken() external view returns (address);

  function assetToken() external view returns (address);

  function vaultPhase() external view returns (Constants.VaultPhase);

  function vaultState() external view returns (Constants.VaultState memory);
  
}