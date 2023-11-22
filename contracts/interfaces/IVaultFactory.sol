// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IVaultFactory {

  function getVaultAddress(address assetToken) external view returns (address);

  function isVault(address addr) external view returns (bool);

  function assetTokens() external view returns (address[] memory);
  
  function addVault(address vaultCalculator, address assetToken, address assetPriceFeed, address leveragedToken, bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues) external;

}