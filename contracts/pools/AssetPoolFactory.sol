// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./AssetPool.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetPoolFactory.sol";
import "../WandProtocol.sol";

contract AssetPoolFactory is IAssetPoolFactory, Context, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  address public immutable wandProtocol;
  address public immutable usbToken;

  EnumerableSet.AddressSet private _assetTokens;
  EnumerableSet.AddressSet private _assetPools;
  /// @dev Mapping from asset token to AssetPoolInfo.
  mapping(address => AssetPoolInfo) private _assetPoolsByAssetToken;

  struct AssetPoolInfo {
    address pool;
    address assetToken;
    address assetPriceFeed;
  }

  constructor(address _wandProtocol, address _usbToken) {
    require(_wandProtocol != address(0), "Zero address detected");
    require(_usbToken != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
    usbToken = _usbToken;
  }

  /**
   * @dev No guarantees are made on the ordering of the assets, and it should not be relied upon.
   */
  function assetTokens() public view returns (address[] memory) {
    return _assetTokens.values();
  }

  function getAssetPoolInfo(address assetToken) external view returns (AssetPoolInfo memory) {
    require(_assetTokens.contains(assetToken), "Invalid asset token");
    return _assetPoolsByAssetToken[assetToken];
  }

  function addAssetPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol) external nonReentrant onlyProtocol {
    require(assetToken != address(0), "Zero address detected");
    require(assetPriceFeed != address(0), "Zero address detected");
    require(bytes(xTokenName).length > 0, "Empty x token name");
    require(bytes(xTokenSymbol).length > 0, "Empty x token symbol");
    require(!_assetTokens.contains(assetToken), "Already added pool for asset token");

    AssetPoolInfo storage poolInfo = _assetPoolsByAssetToken[assetToken];
    require(poolInfo.pool == address(0), "AssetPool already exists");

    poolInfo.pool = address(new AssetPool(wandProtocol, address(this), assetToken, assetPriceFeed, usbToken, xTokenName, xTokenSymbol));
    poolInfo.assetToken = assetToken;
    poolInfo.assetPriceFeed = assetPriceFeed;

    _assetTokens.add(assetToken);
    _assetPools.add(poolInfo.pool);

    emit AssetPoolAdded(assetToken, assetPriceFeed, poolInfo.pool);
  }

  /* ========== IAssetPoolFactory ========== */

  function isAssetPool(address poolAddress) external view returns (bool) {
    require(poolAddress != address(0), "Zero address detected");
    return _assetPools.contains(poolAddress);
  }

  function setRedemptionFeeWithUSBTokens(address assetToken, uint256 newRedemptionFeeWithUSBTokens) external nonReentrant onlyValidAssetToken(assetToken) {
    AssetPoolInfo memory poolInfo = _assetPoolsByAssetToken[assetToken];
    IAssetPool(poolInfo.pool).setRedemptionFeeWithUSBTokens(newRedemptionFeeWithUSBTokens);
  }

  function setRedemptionFeeWithXTokens(address assetToken,  uint256 newRedemptionFeeWithXTokens) external nonReentrant onlyValidAssetToken(assetToken) {
    AssetPoolInfo memory poolInfo = _assetPoolsByAssetToken[assetToken];
    IAssetPool(poolInfo.pool).setRedemptionFeeWithXTokens(newRedemptionFeeWithXTokens);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  modifier onlyValidAssetToken(address assetToken) {
    require(_assetPoolsByAssetToken[assetToken].pool != address(0), "Invalid asset token");
    _;
  }

  /* =============== EVENTS ============= */

  event AssetPoolAdded(address indexed assetToken, address assetPriceFeed, address pool);
}