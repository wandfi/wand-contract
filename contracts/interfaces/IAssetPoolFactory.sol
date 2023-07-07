// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IAssetPoolFactory {

  function isAssetPool(address addr) external view returns (bool);

  function assetTokens() external view returns (address[] memory);
  
  function addAssetPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol) external;

  function getAssetPoolXToken(address assetToken) external view returns (address);

  function setRedemptionFeeWithUSBTokens(address assetToken, uint256 newRedemptionFeeWithUSBTokens) external;

  function setRedemptionFeeWithXTokens(address assetToken,  uint256 newRedemptionFeeWithXTokens) external;
}