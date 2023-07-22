// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/utils/Context.sol";
// import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./AssetPool.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetPoolFactory.sol";

contract AssetPoolFactory is IAssetPoolFactory {
  // using EnumerableSet for EnumerableSet.AddressSet;

  address public immutable wandProtocol;
  // address public immutable usbToken;

  // EnumerableSet.AddressSet internal _assetTokens;
  // EnumerableSet.AddressSet internal _assetPools;
  address[] internal _assetTokens;
  

  /// @dev Mapping from asset token to AssetPoolInfo.
  // mapping(address => AssetPoolInfo) internal _assetTokenToPools;

  mapping(address => address) internal _assetTokenToPools;
  mapping(address => address) internal _poolToAssetTokens;

  // struct AssetPoolInfo {
  //   address pool;
  //   address assetToken;
  //   address assetPriceFeed;
  //   address xToken;
  // }

  constructor(address _wandProtocol) {
    require(_wandProtocol != address(0), "Zero address detected");
    // require(_usbToken != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
    // usbToken = _usbToken;
  }

  /**
   * @dev No guarantees are made on the ordering of the assets, and it should not be relied upon.
   */
  function assetTokens() public view returns (address[] memory) {
    return _assetTokens;
  }

  // function getAssetPoolInfo(address assetToken) external view returns (AssetPoolInfo memory) {
  //   require(_assetTokens.contains(assetToken), "Invalid asset token");
  //   return _assetTokenToPools[assetToken];
  // }

  // function getAssetPoolXToken(address assetToken) external view returns (address) {
  //   require(_assetTokens.contains(assetToken), "Invalid asset token");
  //   return _assetTokenToPools[assetToken].xToken;
  // }

  function addAssetPool(
    // address assetPoolCalculator, address assetToken, address assetPriceFeed, string memory xTokenName, string memory xTokenSymbol,
    // uint256 Y, uint256 AART, uint256 AARS, uint256 AARC
    address assetToken, address assetPriceFeed, address xToken,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  ) external onlyProtocol {
    // address assetPoolCalculator = assetInfo[0];
    // address assetToken = assetInfo[0];
    // address assetPriceFeed = assetInfo[1];

    // string memory xTokenName = xTokenInfo[0];
    // string memory xTokenSymbol = xTokenInfo[0];
    // uint256 Y = assetPoolParams[0];
    // uint256 AART = assetPoolParams[0];
    // uint256 AARS = assetPoolParams[0];
    // uint256 AARC = assetPoolParams[0];

    require(assetToken != address(0), "Zero address detected");
    require(assetPriceFeed != address(0), "Zero address detected");

    // require(bytes(xTokenName).length > 0, "Empty x token name");
    // require(bytes(xTokenSymbol).length > 0, "Empty x token symbol");
    // require(!_assetTokens.contains(assetToken), "Already added pool for asset token");

    require(_assetTokenToPools[assetToken] == address(0), "AssetPool already exists");

    // poolInfo.pool = address(new AssetPool(wandProtocol, address(this), assetPoolCalculator, assetToken, assetPriceFeed, usbToken, xTokenName, xTokenSymbol, Y, AART, AARS, AARC));
    address pool = address(new AssetPool(wandProtocol, assetToken, assetPriceFeed, xToken, assetPoolParams, assetPoolParamsValues));

    // poolInfo.assetToken = assetToken;
    // poolInfo.assetPriceFeed = assetPriceFeed;
    // poolInfo.xToken = IAssetPool(poolInfo.pool).xToken();

    _assetTokens.push(assetToken);
    _assetTokenToPools[assetToken] = pool;
    _poolToAssetTokens[pool] = assetToken;
    // _assetPools.add(_assetTokenToPools[assetToken]);

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

  // function setC1(address assetToken, uint256 newC1) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setC1(newC1);
  // }

  // function setC2(address assetToken,  uint256 newC2) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setC2(newC2);
  // }

  // function setY(address assetToken, uint256 newY) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setY(newY);
  // }

  // function setBasisR(address assetToken, uint256 newBasisR) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setBasisR(newBasisR);
  // }

  // function setRateR(address assetToken, uint256 newRateR) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setRateR(newRateR);
  // }

  // function setBasisR2(address assetToken, uint256 newBasisR2) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setBasisR2(newBasisR2);
  // }

  // function setCiruitBreakPeriod(address assetToken, uint256 newCiruitBreakPeriod) external nonReentrant onlyValidAssetToken(assetToken) {
  //   // AssetPoolInfo memory poolInfo = _assetTokenToPools[assetToken];
  //   IAssetPool(_assetTokenToPools[assetToken]).setCiruitBreakPeriod(newCiruitBreakPeriod);
  // }

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