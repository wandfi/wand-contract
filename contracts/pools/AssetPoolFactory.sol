// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "./AssetPool.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetPoolFactory.sol";

contract AssetPoolFactory is IAssetPoolFactory {

  address public immutable wandProtocol;

  address[] internal _assetTokens;

  mapping(address => address) internal _assetTokenToPools;
  mapping(address => address) internal _poolToAssetTokens;

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

  function addAssetPool(
    address assetToken, address assetPriceFeed, address xToken,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  ) external onlyProtocol {
    require(assetToken != address(0), "Zero address detected");
    require(assetPriceFeed != address(0), "Zero address detected");

    require(_assetTokenToPools[assetToken] == address(0), "AssetPool already exists");

    address pool = address(new AssetPool(wandProtocol, assetToken, assetPriceFeed, xToken, assetPoolParams, assetPoolParamsValues));

    _assetTokens.push(assetToken);
    _assetTokenToPools[assetToken] = pool;
    _poolToAssetTokens[pool] = assetToken;

    emit AssetPoolAdded(assetToken, assetPriceFeed, _assetTokenToPools[assetToken]);
  }

  /* ========== IAssetPoolFactory ========== */

  function getAssetPoolAddress(address assetToken) external view override returns (address) {
    require(_assetTokenToPools[assetToken] != address(0), "Invalid asset token");
    return _assetTokenToPools[assetToken];
  }

  function isAssetPool(address poolAddress) external view returns (bool) {
    require(poolAddress != address(0), "Zero address detected");
    return _poolToAssetTokens[poolAddress] != address(0);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(msg.sender == wandProtocol, "Caller is not protocol");
    _;
  }

  modifier onlyValidAssetToken(address assetToken) {
    require(_assetTokenToPools[assetToken] != address(0), "Invalid asset token");
    _;
  }

  /* =============== EVENTS ============= */

  event AssetPoolAdded(address indexed assetToken, address assetPriceFeed, address pool);
}