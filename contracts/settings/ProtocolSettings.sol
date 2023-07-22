// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IProtocolSettings.sol";
import "../libs/Constants.sol";

contract ProtocolSettings is IProtocolSettings, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.Bytes32Set;

  address internal _treasury;

  struct ParamConfig {
    uint256 defaultValue;
    uint256 min;
    uint256 max;
  }

  EnumerableSet.Bytes32Set internal _paramsSet;
  mapping(bytes32 => ParamConfig) internal _paramConfigs;
  mapping(address => mapping(bytes32 => uint256)) internal _assetPoolParams;

  constructor(address _treasury_) Ownable() {
    _treasury = _treasury_;

    // Redemption fee rate with $USB. Default to 0.1%. [0, 10%]
    _upsertParamConfig("C1", 1 * 10 ** 7, 0, 10 ** 9);
    // Redemption fee rate with X tokens paired with $USB. Default to 0.5%. [0, 10%]
    _upsertParamConfig("C2", 5 * 10 ** 7, 0, 10 ** 9);
    // Yield rate. Default to 3.5%, [0, 50%]
    _upsertParamConfig("Y", 35 * 10 ** 7, 0, 5 * 10 ** 9);
    // Basis of r. Default to 0.1, [0, 1]
    _upsertParamConfig("BasisR", 10 ** 9, 0, 10 ** 10);
    // Rate of r change per hour. Default to 0.001, [0, 1]
    _upsertParamConfig("RateR", 10 ** 7, 0, 10 ** 10);
    // Basis of R2. Default to 0.06, [0, 1]
    _upsertParamConfig("BasisR2", 6 * 10 ** 8, 0, 10 ** 10);
    // Circuit breaker period. Default to 1 hour, [1 minute, 1 day]
    _upsertParamConfig("CircuitBreakPeriod", 1 hours, 1 minutes, 1 days);
    // X Tokens transfer fee. Default to 0.08%, [0, 100%]
    _upsertParamConfig("XTokensTransferFee", 8 * 10 ** 6, 0, 10 ** 10);
    // Target AAR. Default 200%, [100%, 1000%]
    _upsertParamConfig("AART", 2 * 10 ** 10, 10 ** 10, 10 ** 11);
    // Safe AAR. Default 150%, [100%, 1000%]
    _upsertParamConfig("AARS", 15 * 10 ** 9, 10 ** 10, 10 ** 11);
    // Circuit Breaker AAR. Default 110%, [100%, 1000%]
    _upsertParamConfig("AARC", 11 * 10 ** 9, 10 ** 10, 10 ** 11);
  }

  /* ============== VIEWS =============== */

  function treasury() public view override returns (address) {
    return _treasury;
  }

  function decimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function params() public view returns (bytes32[] memory) {
    return _paramsSet.values();
  }

  function paramConfig(bytes32 param) public view returns(ParamConfig memory) {
    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    return _paramConfigs[param];
  }

  function paramDefaultValue(bytes32 param) public view returns (uint256) {
    return paramConfig(param).defaultValue;
  }

  function assetPoolParamValue(address assetPool, bytes32 param) public view returns (uint256) {
    require(assetPool != address(0), "Zero address detected");
    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    return _assetPoolParams[assetPool][param];
  }

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setTreasury(address newTreasury) public nonReentrant onlyOwner {
    require(newTreasury != address(0), "Zero address detected");
    require(newTreasury != _treasury, "Same _treasury");

    address prevTreasury = _treasury;
    _treasury = newTreasury;
    emit UpdateTreasury(prevTreasury, _treasury);
  }

  function _upsertParamConfig(bytes32 param, uint256 defaultValue, uint256 min, uint256 max) internal onlyOwner {
    require(param.length > 0, "Empty param name");
    require(min <= defaultValue && defaultValue <= max, "Invalid default value");
    require(min <= max, "Invalid min and max");

    _paramsSet.add(param);
    _paramConfigs[param] = ParamConfig(defaultValue, min, max);
    emit UpsertParamConfig(param, defaultValue, min, max);
  }

  function updateAssetPoolParam(address assetPool, bytes32 param, uint256 value) public nonReentrant onlyOwner {
    require(assetPool != address(0), "Zero address detected");
    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    require(_paramConfigs[param].min <= value && value <= _paramConfigs[param].max, "Invalid value");

    _assetPoolParams[assetPool][param] = value;
    emit UpdateAssetPoolParamValue(assetPool, param, value);
  }

  /* =============== EVENTS ============= */

  event UpsertParamConfig(bytes32 indexed name, uint256 defaultValue, uint256 min, uint256 max);
  event UpdateAssetPoolParamValue(address indexed assetPool, bytes32 indexed param, uint256 value);

  event UpdateTreasury(address prevTreasury, address newTreasury);
}