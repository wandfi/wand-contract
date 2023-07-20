// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./interest/InterestPoolFactory.sol";
import "./interfaces/IAssetPoolFactory.sol";
import "./interfaces/IInterestPoolFactory.sol";
import "./pools/AssetPoolFactory.sol";
import "./settings/ProtocolSettings.sol";
import "./tokens/USB.sol";

contract WandProtocol is Ownable, ReentrancyGuard {

  address public settings;
  address public usbToken;
  address public assetPoolFactory;
  address public interestPoolFactory;

  bool public initialized;

  constructor() Ownable() {

  }

  function initialize() external nonReentrant onlyOwner {
    require(!initialized, "Already initialized");

    settings = address(new ProtocolSettings(address(this), _msgSender()));
    usbToken = address(new USB(address(this), "USB Token", "USB"));
    assetPoolFactory = address(new AssetPoolFactory(address(this), usbToken));
    interestPoolFactory = address(new InterestPoolFactory(address(this)));

    initialized = true;
    emit Initialized();
  }

  /* ========== Asset Pool Operations ========== */

  function addAssetPool(
    address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol,
    uint256 Y, uint256 AART, uint256 AARS, uint256 AARC
  ) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).addAssetPool(assetToken, assetPriceFeed, xTokenName, xTokenSymbol, Y, AART, AARS, AARC);

    // Add newly created X token to all interest pools
    address xToken = IAssetPoolFactory(assetPoolFactory).getAssetPoolXToken(assetToken);

    // Make sure $USB interest pool is created
    if (!IInterestPoolFactory(interestPoolFactory).poolExists(usbToken)) {
      address[] memory rewardTokons = new address[](1);
      rewardTokons[0] = xToken;
      IInterestPoolFactory(interestPoolFactory).addInterestPool(usbToken, Constants.InterestPoolStakingTokenType.Usb, address(0), 0, rewardTokons);
    }
    
    // Now iterate all interest pools and add the new X token (if not already added)
    IInterestPoolFactory(interestPoolFactory).addRewardTokenToAllPools(xToken);
  }

  /* ========== Interest Pool Operations ========== */

  function addUsbInterestPool() external onlyInitialized nonReentrant onlyOwner {
    address[] memory rewardTokens = _getXTokenList();
    IInterestPoolFactory(interestPoolFactory).addInterestPool(usbToken, Constants.InterestPoolStakingTokenType.Usb, address(0), 0, rewardTokens);
  }

  function addUniLpInterestPool(address lpToken) external onlyInitialized nonReentrant onlyOwner {
    address[] memory rewardTokens = _getXTokenList();
    IInterestPoolFactory(interestPoolFactory).addInterestPool(lpToken, Constants.InterestPoolStakingTokenType.UniswapV2PairLp, address(0), 0, rewardTokens);
  }

  function addCurveLpInterestPool(address lpToken, address swapPool, uint256 swapPoolCoinsCount) external onlyInitialized nonReentrant onlyOwner {
    address[] memory rewardTokens = _getXTokenList();
    IInterestPoolFactory(interestPoolFactory).addInterestPool(lpToken, Constants.InterestPoolStakingTokenType.CurvePlainPoolLp, swapPool, swapPoolCoinsCount, rewardTokens);
  }

  function addRewardTokenToInterestPool(address stakingToken, address rewardToken) public onlyInitialized nonReentrant onlyOwner {
    IInterestPoolFactory(interestPoolFactory).addRewardToken(stakingToken, rewardToken);
  }

  function _getXTokenList() internal view returns (address[] memory) {
    // Get reward token list (currently only x tokens)
    IAssetPoolFactory iAssetPoolFactory = IAssetPoolFactory(assetPoolFactory);
    address[] memory assetTokens = iAssetPoolFactory.assetTokens();
    require(assetTokens.length > 0, "No asset pools created yet");

    address[] memory xTokens = new address[](assetTokens.length);
    for (uint256 i = 0; i < assetTokens.length; i++) {
      xTokens[i] = iAssetPoolFactory.getAssetPoolXToken(assetTokens[i]);
    }

    return xTokens;
  }

  /* ========== Update Protocol Settings ========== */

  function setTreasury(address newTreasury) external onlyInitialized nonReentrant onlyOwner {
    IProtocolSettings(settings).setTreasury(newTreasury);
  }

  function setDefaultC1(uint256 newDefaultC1) external onlyInitialized nonReentrant onlyOwner {
    IProtocolSettings(settings).setDefaultC1(newDefaultC1);
  }

  function setDefaultC2(uint256 newDefaultC2) external onlyInitialized nonReentrant onlyOwner {
    IProtocolSettings(settings).setDefaultC2(newDefaultC2);
  }

  function setC1(address assetToken, uint256 newC1) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setC1(assetToken, newC1);
  }

  function setC2(address assetToken,  uint256 newC2) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setC2(assetToken, newC2);
  }

  function setY(address assetToken, uint256 newY) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setY(assetToken, newY);
  }

  function setBasisR(address assetToken, uint256 newBasisR) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setBasisR(assetToken, newBasisR);
  }

  function setRateR(address assetToken, uint256 newRateR) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setRateR(assetToken, newRateR);
  }

  function setBasisR2(address assetToken, uint256 newBasisR2) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setBasisR2(assetToken, newBasisR2);
  }

  function setCiruitBreakPeriod(address assetToken, uint256 newCiruitBreakPeriod) external onlyInitialized nonReentrant onlyOwner {
    IAssetPoolFactory(assetPoolFactory).setCiruitBreakPeriod(assetToken, newCiruitBreakPeriod);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyInitialized() {
    require(initialized, "Contract is not initialized");
    _;
  }

  /* =============== EVENTS ============= */

  event Initialized();

}