// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IWandProtocol {

  /* ============ VIEWS =========== */

  function protocolOwner() external view returns (address);

  function settings() external view returns (address);

  function usbToken() external view returns (address);

  function vaultCalculator() external view returns (address);

  function vaultFactory() external view returns (address);

  function interestPoolFactory() external view returns (address);

  // function setUsbToken(address newUsbToken) external;

  // function setAssetPoolFactory(address newAssetPoolFactory) external;

}