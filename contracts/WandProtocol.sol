// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./interfaces/IVault.sol";
import "./interfaces/IWandProtocol.sol";
import "./settings/ProtocolSettings.sol";

contract WandProtocol is IWandProtocol, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  address internal immutable _settings;
  address internal _usbToken;

  address[] internal _assetTokens;
  mapping(address => address) internal _assetTokenToVaults;
  mapping(address => address) internal _vaultToAssetTokens;

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

  /* ========== Initialization Operations ========= */

  function initialize(address _usbToken_) external nonReentrant onlyOwner {
    require(!initialized, "Already initialized");
    require(_usbToken_ != address(0), "Zero address detected");

    _usbToken = _usbToken_;

    initialized = true;
    emit Initialized();
  }

  /* ========== Vault Operations ========== */

  function addVault(IVault vault) external nonReentrant onlyOwner onlyInitialized {
    address assetToken = vault.assetToken();
    require(_assetTokenToVaults[assetToken] == address(0), "Vault already exists");

    _assetTokens.push(assetToken);
    _assetTokenToVaults[assetToken] = address(vault);
    _vaultToAssetTokens[address(vault)] = assetToken;

    emit VaultAdded(assetToken, vault.assetTokenPriceFeed(), _assetTokenToVaults[assetToken]);
  }

  function assetTokens() public view returns (address[] memory) {
    return _assetTokens;
  }

  function isVault(address vaultAddress) external view returns (bool) {
    require(vaultAddress != address(0), "Zero address detected");
    return _vaultToAssetTokens[vaultAddress] != address(0);
  }

  function getVaultAddress(address assetToken) external view returns (address) {
    require(_assetTokenToVaults[assetToken] != address(0), "Invalid asset token");
    return _assetTokenToVaults[assetToken];
  }

  /* ============== MODIFIERS =============== */

  modifier onlyInitialized() {
    require(initialized, "Not initialized yet");
    _;
  }

  /* =============== EVENTS ============= */

  event Initialized();

  event VaultAdded(address indexed assetToken, address assetPriceFeed, address vault);

}