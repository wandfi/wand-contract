// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IAssetPoolFactory {

  function isAssetPool(address addr) external view returns (bool);
  
  function addAssetPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol) external;

  function setRedemptionFeeWithUSBTokens(address assetToken, uint256 newRedemptionFeeWithUSBTokens) external;

  function setRedemptionFeeWithXTokens(address assetToken,  uint256 newRedemptionFeeWithXTokens) external;
}