// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./interfaces/IWandProtocol.sol";
import "./interfaces/IAssetPoolFactory.sol";
import "./interfaces/IAssetPool.sol";
import "./interfaces/IInterestPoolFactory.sol";
import "./settings/ProtocolSettings.sol";
// import "./tokens/USB.sol";
// import "./pools/AssetPool.sol";

contract WandProtocol is IWandProtocol, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  address internal immutable _settings;

  address internal _usbToken;
  address internal _assetPoolFactory;
  address internal _interestPoolFactory;
  address internal _assetPoolCalculator;

  EnumerableSet.AddressSet internal _assetTokens;
  mapping(address => address) internal _assetPoolsByAssetToken;

  constructor(address _settings_) Ownable() {
    require(_settings_ != address(0), "Zero address detected");
    _settings = _settings_;
  }

  /* ========== Views ========= */

  function protocolOwner() public view returns (address) {
    return owner();
  }

  function settings() public view override returns (address) {
    return _settings;
  }

  function usbToken() public view override returns (address) {
    return _usbToken;
  }

  function assetPoolCalculator() public view override returns (address) {
    return _assetPoolCalculator;
  }

  function assetPoolFactory() public view override returns (address) {
    return _assetPoolFactory;
  }

  function interestPoolFactory() public view override returns (address) {
    return _interestPoolFactory;
  }

  /* ========== Initialization Operations ========= */

  // function setSettings(address newSettings) external nonReentrant onlyOwner {
  //   require(newSettings != address(0), "Zero address detected");
  //   _settings = newSettings;
  // }

  function setUsbToken(address newUsbToken) external nonReentrant onlyOwner {
    require(newUsbToken != address(0), "Zero address detected");
    _usbToken = newUsbToken;
  }

  function setAssetPoolFactory(address newAssetPoolFactory) external nonReentrant onlyOwner {
    require(newAssetPoolFactory != address(0), "Zero address detected");
    _assetPoolFactory = newAssetPoolFactory;
  }

  function setInterestPoolFactory(address newInterestPoolFactory) external nonReentrant onlyOwner {
    require(newInterestPoolFactory != address(0), "Zero address detected");
    _interestPoolFactory = newInterestPoolFactory;
  }

  function setAssetPoolCalculator(address newAssetPoolCalculator) external nonReentrant onlyOwner {
    require(newAssetPoolCalculator != address(0), "Zero address detected");
    _assetPoolCalculator = newAssetPoolCalculator;
  }

  /* ========== Asset Pool Operations ========== */

  function addAssetPool(
    // address assetPoolCalculator, address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol,
    // uint256 Y, uint256 AART, uint256 AARS, uint256 AARC
    // address[] memory assetInfo, uint256[] memory assetPoolParams
    address assetToken, address assetPriceFeed, address xToken,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  ) external onlyInitialized nonReentrant onlyOwner {

    // IAssetPoolFactory(_assetPoolFactory).addAssetPool(_assetPoolCalculator, assetToken, assetPriceFeed, xTokenName, xTokenSymbol, Y, AART, AARS, AARC);
    IAssetPoolFactory(_assetPoolFactory).addAssetPool(assetToken, assetPriceFeed, xToken, assetPoolParams, assetPoolParamsValues);

    // Add newly created X token to all interest pools
    // address assetToken = assetInfo[1];
    // address xToken = IAssetPool(IAssetPoolFactory(_assetPoolFactory).getAssetPoolAddress(assetToken)).xToken();

    // Make sure $USB interest pool is created

    // if (!IInterestPoolFactory(_interestPoolFactory).poolExists(_usbToken)) {
    //   address[] memory rewardTokons = new address[](1);
    //   rewardTokons[0] = xToken;
    //   IInterestPoolFactory(_interestPoolFactory).addInterestPool(_usbToken, Constants.InterestPoolStakingTokenType.Usb, address(0), 0, rewardTokons);
    // }
    
    // Now iterate all interest pools and add the new X token (if not already added)
    IInterestPoolFactory(_interestPoolFactory).addRewardTokenToAllPools(xToken);
  }

  /* ========== Interest Pool Operations ========== */

  // function addUsbInterestPool() external onlyInitialized nonReentrant onlyOwner {
  //   address[] memory rewardTokens = _getXTokenList();
  //   IInterestPoolFactory(_interestPoolFactory).addInterestPool(_usbToken, Constants.InterestPoolStakingTokenType.Usb, address(0), 0, rewardTokens);
  // }

  // function addUniLpInterestPool(address lpToken) external onlyInitialized nonReentrant onlyOwner {
  //   address[] memory rewardTokens = _getXTokenList();
  //   IInterestPoolFactory(_interestPoolFactory).addInterestPool(lpToken, Constants.InterestPoolStakingTokenType.UniswapV2PairLp, address(0), 0, rewardTokens);
  // }

  // function addCurveLpInterestPool(address lpToken, address swapPool, uint256 swapPoolCoinsCount) external onlyInitialized nonReentrant onlyOwner {
  //   address[] memory rewardTokens = _getXTokenList();
  //   IInterestPoolFactory(_interestPoolFactory).addInterestPool(lpToken, Constants.InterestPoolStakingTokenType.CurvePlainPoolLp, swapPool, swapPoolCoinsCount, rewardTokens);
  // }

  function addRewardTokenToInterestPool(address stakingToken, address rewardToken) public onlyInitialized nonReentrant onlyOwner {
    IInterestPoolFactory(_interestPoolFactory).addRewardToken(stakingToken, rewardToken);
  }

  function _getXTokenList() internal view returns (address[] memory) {
    // Get reward token list (currently only x tokens)
    IAssetPoolFactory iAssetPoolFactory = IAssetPoolFactory(_assetPoolFactory);
    address[] memory assetTokens = iAssetPoolFactory.assetTokens();
    require(assetTokens.length > 0, "No asset pools created yet");

    address[] memory xTokens = new address[](assetTokens.length);
    for (uint256 i = 0; i < assetTokens.length; i++) {
      // xTokens[i] = iAssetPoolFactory.getAssetPoolXToken(assetTokens[i]);
      xTokens[i] = IAssetPool(IAssetPoolFactory(_assetPoolFactory).getAssetPoolAddress(assetTokens[i])).xToken();
    }

    return xTokens;
  }

  /* ========== Update Protocol Settings ========== */

  // function setTreasury(address newTreasury) external onlyInitialized nonReentrant onlyOwner {
  //   IProtocolSettings(_settings).setTreasury(newTreasury);
  // }

  // function setDefaultC1(uint256 newDefaultC1) external onlyInitialized nonReentrant onlyOwner {
  //   IProtocolSettings(_settings).setDefaultC1(newDefaultC1);
  // }

  // function setDefaultC2(uint256 newDefaultC2) external onlyInitialized nonReentrant onlyOwner {
  //   IProtocolSettings(_settings).setDefaultC2(newDefaultC2);
  // }

  // function setC1(address assetToken, uint256 newC1) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setC1(assetToken, newC1);
  // }

  // function setC2(address assetToken,  uint256 newC2) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setC2(assetToken, newC2);
  // }

  // function setY(address assetToken, uint256 newY) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setY(assetToken, newY);
  // }

  // function setBasisR(address assetToken, uint256 newBasisR) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setBasisR(assetToken, newBasisR);
  // }

  // function setRateR(address assetToken, uint256 newRateR) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setRateR(assetToken, newRateR);
  // }

  // function setBasisR2(address assetToken, uint256 newBasisR2) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setBasisR2(assetToken, newBasisR2);
  // }

  // function setCiruitBreakPeriod(address assetToken, uint256 newCiruitBreakPeriod) external onlyInitialized nonReentrant onlyOwner {
  //   IAssetPoolFactory(_assetPoolFactory).setCiruitBreakPeriod(assetToken, newCiruitBreakPeriod);
  // }

  /* ============== MODIFIERS =============== */

  modifier onlyInitialized() {
    // require(_settings != address(0), "Settings not set");
    require(_usbToken != address(0), "USB Token not set");
    require(_assetPoolFactory != address(0), "AssetPoolFactory not set");
    require(_interestPoolFactory != address(0), "InterestPoolFactory not set");
    require(_assetPoolCalculator != address(0), "AssetPoolCalculator not set");
    _;
  }

}