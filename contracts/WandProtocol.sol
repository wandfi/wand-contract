// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./interfaces/IAssetPoolFactory.sol";
import "./interfaces/IAssetPool.sol";
import "./interfaces/IInterestPoolFactory.sol";
import "./interfaces/IWandProtocol.sol";
import "./settings/ProtocolSettings.sol";

contract WandProtocol is IWandProtocol, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  address internal immutable _settings;

  address internal _usbToken;
  address internal _assetPoolFactory;
  address internal _interestPoolFactory;
  address internal _assetPoolCalculator;

  bool public initialized;

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

  function initialize(address _usbToken_, address _assetPoolCalculator_, address _assetPoolFactory_, address _interestPoolFactory_) external nonReentrant onlyOwner {
    require(!initialized, "Already initialized");
    require(_usbToken_ != address(0), "Zero address detected");
    require(_assetPoolCalculator_ != address(0), "Zero address detected");
    require(_assetPoolFactory_ != address(0), "Zero address detected");
    require(_interestPoolFactory_ != address(0), "Zero address detected");

    _usbToken = _usbToken_;
    _assetPoolCalculator = _assetPoolCalculator_;
    _assetPoolFactory = _assetPoolFactory_;
    _interestPoolFactory = _interestPoolFactory_;

    initialized = true;
    emit Initialized();
  }

  /* ========== Asset Pool Operations ========== */

  function addAssetPool(
    address assetToken, address assetPriceFeed, address xToken,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  ) external onlyInitialized nonReentrant onlyOwner {

    IAssetPoolFactory(_assetPoolFactory).addAssetPool(assetToken, assetPriceFeed, xToken, assetPoolParams, assetPoolParamsValues);

    // Now iterate all interest pools and add the new X token (if not already added)
    IInterestPoolFactory(_interestPoolFactory).addRewardTokenToAllPools(xToken);
  }

  /* ========== Interest Pool Operations ========== */

  function addRewardTokenToInterestPool(address stakingToken, address rewardToken) public onlyInitialized nonReentrant onlyOwner {
    IInterestPoolFactory(_interestPoolFactory).addRewardToken(stakingToken, rewardToken);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyInitialized() {
    require(initialized, "Not initialized yet");
    _;
  }

  /* =============== EVENTS ============= */

  event Initialized();

}