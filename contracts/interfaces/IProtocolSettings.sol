// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IProtocolSettings {

  /* ============ VIEWS =========== */

  function treasury() external view returns (address);

  function decimals() external view returns (uint256);

  function paramDefaultValue(bytes32 param) external view returns (uint256);

  function assetPoolParamValue(address assetPool, bytes32 param) external view returns (uint256);

  /* ============ MUTATIVE FUNCTIONS =========== */

  function updateAssetPoolParam(address assetPool, bytes32 param, uint256 value) external;
}