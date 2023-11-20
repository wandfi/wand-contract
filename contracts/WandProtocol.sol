// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IWandProtocol.sol";
import "./settings/ProtocolSettings.sol";

contract WandProtocol is IWandProtocol, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  address internal immutable _settings;

  address internal _usbToken;
  address internal _vaultFactory;

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

  function vaultFactory() public view override returns (address) {
    return _vaultFactory;
  }

  /* ========== Initialization Operations ========= */

  function initialize(address _usbToken_, address _vaultFactory_) external nonReentrant onlyOwner {
    require(!initialized, "Already initialized");
    require(_usbToken_ != address(0), "Zero address detected");
    require(_vaultFactory_ != address(0), "Zero address detected");

    _usbToken = _usbToken_;
    _vaultFactory = _vaultFactory_;

    initialized = true;
    emit Initialized();
  }

  /* ========== Asset Pool Operations ========== */

  function addVault(
    address assetToken, address assetPriceFeed, address leveragedToken,
    bytes32[] memory vaultParams, uint256[] memory vaultParamsValues
  ) external onlyInitialized nonReentrant onlyOwner {

    IVaultFactory(_vaultFactory).addVault(assetToken, assetPriceFeed, leveragedToken, vaultParams, vaultParamsValues);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyInitialized() {
    require(initialized, "Not initialized yet");
    _;
  }

  /* =============== EVENTS ============= */

  event Initialized();

}