// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IWandProtocol {

  function protocolOwner() external view returns (address);

  function settings() external view returns (address);

  function usbToken() external view returns (address);

  function isVault(address vaultAddress) external view returns (bool);
}