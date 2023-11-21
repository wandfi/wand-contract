// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

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

  constructor(address _treasury_) Ownable() {
    _treasury = _treasury_;

    // Redemption fee rate with $USB. Default to 0.1%. [0, 10%]
    _upsertParamConfig("C1", 1 * 10 ** 7, 0, 10 ** 9);
    // Redemption fee rate with X tokens paired with $USB. Default to 0.5%. [0, 10%]
    _upsertParamConfig("C2", 5 * 10 ** 7, 0, 10 ** 9);
    // Yield rate. Default to 3.5%, [0, 50%]
    _upsertParamConfig("Y", 35 * 10 ** 7, 0, 5 * 10 ** 9);
    // Rate of r change per hour. Default to 0.001, [0, 1]
    _upsertParamConfig("RateR", 10 ** 7, 0, 10 ** 10);
    // Circuit breaker period. Default to 1 hour, [1 minute, 1 day]
    _upsertParamConfig("CircuitBreakPeriod", 1 hours, 1 minutes, 1 days);
    // Leveraged Tokens transfer fee. Default to 0.08%, [0, 100%]
    _upsertParamConfig("LeveragedTokensTransferFee", 8 * 10 ** 6, 0, 10 ** 10);
    // Target AAR. Default 150%, [100%, 1000%]
    _upsertParamConfig("AART", 15 * 10 ** 9, 10 ** 10, 10 ** 11);
    // Safe AAR. Default 130%, [100%, 1000%]
    _upsertParamConfig("AARS", 13 * 10 ** 9, 10 ** 10, 10 ** 11);
    // Upper AAR. Default 200%, [100%, 1000%]
    _upsertParamConfig("AARU", 2 * 10 ** 10, 10 ** 10, 10 ** 11);
    // Circuit Breaker AAR. Default 110%, [100%, 1000%]
    _upsertParamConfig("AARC", 11 * 10 ** 9, 10 ** 10, 10 ** 11);
    // Price Trigger Yield pool, min $USB dust amount. Default 5 $USB, [0, 1000]
    _upsertParamConfig("PtyPoolMinUsbAmount", 5 * 10 ** 10, 0, 1000 * 10 ** 10);
    // Price Trigger Yield pool, min asset dust amount. Default 0.001, [0, 1000]
    _upsertParamConfig("PtyPoolMinAssetAmount", 10 ** 7, 0, 1000 * 10 ** 10);
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

  function isValidParam(bytes32 param, uint256 value) public view returns (bool) {
    if (param.length == 0 || !_paramsSet.contains(param)) {
      return false;
    }

    ParamConfig memory config = _paramConfigs[param];
    return config.min <= value && value <= config.max;
  }

  function paramConfig(bytes32 param) public view returns(ParamConfig memory) {
    // if (!_paramsSet.contains(param)) {
    //   console.log('paramConfig, invalid param: %s', string(abi.encodePacked(param)));
    // }

    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    return _paramConfigs[param];
  }

  function paramDefaultValue(bytes32 param) public view returns (uint256) {
    // if (!_paramsSet.contains(param)) {
    //   console.log('paramDefaultValue, invalid param: %s', string(abi.encodePacked(param)));
    // }

    require(param.length > 0, "Empty param name");
    require(_paramsSet.contains(param), "Invalid param name");
    return paramConfig(param).defaultValue;
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

  /* =============== EVENTS ============= */

  event UpsertParamConfig(bytes32 indexed name, uint256 defaultValue, uint256 min, uint256 max);

  event UpdateTreasury(address prevTreasury, address newTreasury);
}