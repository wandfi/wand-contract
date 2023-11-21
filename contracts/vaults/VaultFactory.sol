// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./Vault.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultFactory.sol";

contract VaultFactory is IVaultFactory {

  address public immutable wandProtocol;

  address[] internal _assetTokens;

  mapping(address => address) internal _assetTokenToVaults;
  mapping(address => address) internal _vaultToAssetTokens;

  constructor(address _wandProtocol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
  }

  /**
   * @dev No guarantees are made on the ordering of the assets, and it should not be relied upon.
   */
  function assetTokens() public view returns (address[] memory) {
    return _assetTokens;
  }

  function addVault(
    address assetToken, address assetPriceFeed, address leveragedToken,
    bytes32[] memory vaultParams, uint256[] memory vaultParamsValues
  ) external onlyProtocol {
    require(assetToken != address(0), "Zero address detected");
    require(assetPriceFeed != address(0), "Zero address detected");

    require(_assetTokenToVaults[assetToken] == address(0), "Vault already exists");

    address pool = address(new Vault(wandProtocol, assetToken, assetPriceFeed, leveragedToken, vaultParams, vaultParamsValues));

    _assetTokens.push(assetToken);
    _assetTokenToVaults[assetToken] = pool;
    _vaultToAssetTokens[pool] = assetToken;

    emit VaultAdded(assetToken, assetPriceFeed, _assetTokenToVaults[assetToken]);
  }

  /* ========== IVaultFactory ========== */

  function getVaultAddress(address assetToken) external view override returns (address) {
    require(_assetTokenToVaults[assetToken] != address(0), "Invalid asset token");
    return _assetTokenToVaults[assetToken];
  }

  function isVault(address vaultAddress) external view returns (bool) {
    require(vaultAddress != address(0), "Zero address detected");
    return _vaultToAssetTokens[vaultAddress] != address(0);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(msg.sender == wandProtocol, "Caller is not protocol");
    _;
  }

  modifier onlyValidAssetToken(address assetToken) {
    require(_assetTokenToVaults[assetToken] != address(0), "Invalid asset token");
    _;
  }

  /* =============== EVENTS ============= */

  event VaultAdded(address indexed assetToken, address assetPriceFeed, address pool);
}