// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interest/InterestPoolFactory.sol";
import "./interfaces/IAssetPoolFactory.sol";
import "./interfaces/IInterestPoolFactory.sol";
import "./pools/AssetPoolFactory.sol";
import "./settings/ProtocolSettings.sol";
import "./tokens/USB.sol";

contract WandProtocol is Ownable, ReentrancyGuard {

  address public immutable settings;
  address public immutable usbToken;
  address public immutable assetPoolFactory;
  address public immutable interestPoolFactory;

  constructor() Ownable() {
    settings = address(new ProtocolSettings(address(this)));
    usbToken = address(new USB(address(this), "USB Token", "USB"));
    assetPoolFactory = address(new AssetPoolFactory(address(this), usbToken));
    interestPoolFactory = address(new InterestPoolFactory(address(this)));
  }

  /* ========== Asset Pool Operations ========== */

  function addAssetPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol) external nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).addAssetPool(assetToken, assetPriceFeed, xTokenName, xTokenSymbol);

    // Add newly created X token to all interest pools
    address xToken = IAssetPoolFactory(assetPoolFactory).getAssetPoolXToken(assetToken);

    // Make sure $USB interest pool is created
    if (!IInterestPoolFactory(interestPoolFactory).poolExists(usbToken)) {
      address[] memory rewardTokons = new address[](1);
      rewardTokons[0] = xToken;
      IInterestPoolFactory(interestPoolFactory).addInterestPool(usbToken, Constants.InterestPoolStakingTokenType.USB, rewardTokons);
    }
    
    // Now iterate all interest pools and add the new X token (if not already added)
    IInterestPoolFactory(interestPoolFactory).addRewardTokenToAllPools(xToken);
  }

  /* ========== Interest Pool Operations ========== */

  function addInterestPool(address stakingToken, Constants.InterestPoolStakingTokenType stakingTokenType) external nonReentrant onlyOwner {
    // Get reward token list (currently only x tokens)
    IAssetPoolFactory iAssetPoolFactory = IAssetPoolFactory(assetPoolFactory);
    address[] memory assetTokens = iAssetPoolFactory.assetTokens();
    require(assetTokens.length > 0, "No asset pools created yet");

    address[] memory rewardTokens = new address[](assetTokens.length);
    for (uint256 i = 0; i < assetTokens.length; i++) {
      rewardTokens[i] = iAssetPoolFactory.getAssetPoolXToken(assetTokens[i]);
    }

    IInterestPoolFactory(interestPoolFactory).addInterestPool(stakingToken, stakingTokenType, rewardTokens);
  }

  function addRewardTokenToInterestPool(address stakingToken, address rewardToken) public nonReentrant onlyOwner {
    IInterestPoolFactory(interestPoolFactory).addRewardToken(stakingToken, rewardToken);
  }

  /* ========== Update Protocol Settings ========== */

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