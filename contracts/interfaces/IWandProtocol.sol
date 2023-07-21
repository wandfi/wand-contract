// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IWandProtocol {

  /* ============ VIEWS =========== */

  function settings() external view returns (address);

  function usbToken() external view returns (address);

  function assetPoolFactory() external view returns (address);

  function interestPoolFactory() external view returns (address);

  /* ============ MUTATIVE FUNCTIONS =========== */



}