// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./tokens/USB.sol";
import "./WandPool.sol";
import "./interfaces/IWandPoolFactory.sol";

contract WandPoolFactory is IWandPoolFactory, Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  address public immutable usbToken;

  EnumerableSet.AddressSet private _assetTokens;
  EnumerableSet.AddressSet private _wandPools;
  /// @dev Mapping from asset token to WandPoolInfo.
  mapping(address => WandPoolInfo) private _wandPoolsByAssetToken;

  struct WandPoolInfo {
    address pool;
    address assetToken;
    address assetPriceFeed;
  }

  constructor() Ownable() {
    usbToken = address(new USB(address(this), "USB Token", "USB"));
  }

  /**
   * @dev No guarantees are made on the ordering of the assets, and it should not be relied upon.
   */
  function assetTokens() public view returns (address[] memory) {
    return _assetTokens.values();
  }

  function getWandPoolInfo(address assetToken) external view returns (WandPoolInfo memory) {
    require(_assetTokens.contains(assetToken), "Invalid asset token");
    return _wandPoolsByAssetToken[assetToken];
  }

  function addPool(address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol) external nonReentrant onlyOwner {
    require(assetToken != address(0), "Zero address detected");
    require(assetPriceFeed != address(0), "Zero address detected");
    require(bytes(xTokenName).length > 0, "Empty x token name");
    require(bytes(xTokenSymbol).length > 0, "Empty x token symbol");
    require(!_assetTokens.contains(assetToken), "Already added pool for asset token");

    WandPoolInfo storage poolInfo = _wandPoolsByAssetToken[assetToken];
    require(poolInfo.pool == address(0), "WandPool already exists");

    poolInfo.pool = address(new WandPool(address(this), assetToken, assetPriceFeed, xTokenName, xTokenSymbol));
    poolInfo.assetToken = assetToken;
    poolInfo.assetPriceFeed = assetPriceFeed;

    _assetTokens.add(assetToken);
    _wandPools.add(poolInfo.pool);

    emit WandPoolAdded(assetToken, assetPriceFeed, poolInfo.pool);
  }

  /* ========== IWandPoolFactory ========== */

  function isWandPool(address poolAddress) external view returns (bool) {
    require(poolAddress != address(0), "Zero address detected");
    return _wandPools.contains(poolAddress);
  }


  /* =============== EVENTS ============= */

  event WandPoolAdded(address indexed assetToken, address assetPriceFeed, address pool);
}