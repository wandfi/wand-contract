// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IAssetPoolFactory {

  function isAssetPool(address addr) external view returns (bool);

  function assetTokens() external view returns (address[] memory);
  
  function addAssetPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol, uint256 Y, uint256 AART, uint256 AARS, uint256 AARC) external;

  function getAssetPoolXToken(address assetToken) external view returns (address);

  function setC1(address assetToken, uint256 newC1) external;

  function setC2(address assetToken,  uint256 newC2) external;

  function setY(address assetToken, uint256 newY) external;
}