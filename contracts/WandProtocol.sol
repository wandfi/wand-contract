// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./pools/AssetPoolFactory.sol";
import "./settings/ProtocolSettings.sol";
import "./tokens/USB.sol";

contract WandProtocol is Ownable, ReentrancyGuard {

  address public immutable settings;
  address public immutable usbToken;
  address public immutable assetPoolFactory;

  constructor() Ownable() {
    settings = address(new ProtocolSettings(address(this)));
    usbToken = address(new USB(address(this), "USB Token", "USB"));
    assetPoolFactory = address(new AssetPoolFactory(address(this), usbToken));
  }

  function addAssetPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol) external nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).addAssetPool(assetToken, assetPriceFeed, xTokenName, xTokenSymbol);
  }

  function setDefaultRedemptionFeeWithUSBTokens(uint256 newDefaultRedemptionFeeWithUSBTokens) external nonReentrant onlyOwner {
    IProtocolSettings(settings).setDefaultRedemptionFeeWithUSBTokens(newDefaultRedemptionFeeWithUSBTokens);
  }

  function setDefaultRedemptionFeeWithXTokens(uint256 newDefaultRedemptionFeeWithXTokens) external nonReentrant onlyOwner {
    IProtocolSettings(settings).setDefaultRedemptionFeeWithXTokens(newDefaultRedemptionFeeWithXTokens);
  }

  function setRedemptionFeeWithUSBTokens(address assetToken, uint256 newRedemptionFeeWithUSBTokens) external nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setRedemptionFeeWithUSBTokens(assetToken, newRedemptionFeeWithUSBTokens);
  }

  function setRedemptionFeeWithXTokens(address assetToken,  uint256 newRedemptionFeeWithXTokens) external nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setRedemptionFeeWithXTokens(assetToken, newRedemptionFeeWithXTokens);
  }
}