// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "../interfaces/IProtocolSettings.sol";
import "../libs/Constants.sol";
import "../WandProtocol.sol";

contract ProtocolSettings is IProtocolSettings, Context, ReentrancyGuard {

  address public immutable wandProtocol;

  // Redemption fee rate with $USB. Default to 0.1%. [0, 10%]
  uint256 private _defaultC1 = 1 * 10 ** 7;
  uint256 public constant MIN_C1 = 0;
  uint256 public constant MAX_C1 = 10 ** 9;

  // Redemption fee rate with X tokens paired with $USB. Default to 0.5%. [0, 10%]
  uint256 private _defaultC2 = 5 * 10 ** 7;
  uint256 public constant MIN_C2 = 0;
  uint256 public constant MAX_C2 = 10 ** 9;

  // Yield rate. [0, 50%]
  uint256 public constant MIN_Y = 0;
  uint256 public constant MAX_Y = 5 * 10 ** 9;

  // Target AAR. Default 200%, [100%, 1000%]
  uint256 public constant MIN_AART = 10 ** 10;
  uint256 public constant MAX_AART = 10 ** 11;

  // Safe AAR. Default 150%, [100%, 1000%]
  uint256 public constant MIN_AARS = 10 ** 10;
  uint256 public constant MAX_AARS = 10 ** 11;

  // Circuit Breaker AAR. Default 110%, [100%, 1000%]
  uint256 public constant MIN_AARC = 10 ** 10;
  uint256 public constant MAX_AARC = 10 ** 11;

  // Basis of r. Default to 0.1, [0, 1]
  uint256 private _defaultBasisR = 10 ** 9;
  uint256 public constant MIN_BASIS_R = 0;
  uint256 public constant MAX_BASIS_R = 10 ** 10;

  // Rate of r change per hour. Default to 0.001, [0.01, 0.1]
  uint256 private _defaultRateR = 10 ** 7;
  uint256 public constant MIN_RATE_R = 10 ** 8;
  uint256 public constant MAX_RATE_R = 10 ** 9;

  // Basis of R2. Default to 0.06, [0, 1]
  uint256 private _defaultBasisR2 = 6 * 10 ** 8;
  uint256 public constant MIN_BASIS_R2 = 0;
  uint256 public constant MAX_BASIS_R2 = 10 ** 10;

  constructor(address _wandProtocol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
  }

  /* ============== VIEWS =============== */

  function decimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function defaultC1() public view returns (uint256) {
    return _defaultC1;
  }

  function defaultC2() public view returns (uint256) {
    return _defaultC2;
  }

  function assertC1(uint256 c1) public pure override {
    require(c1 >= MIN_C1, "C1 too low");
    require(c1 <= MAX_C1, "C1 too high");
  }

  function assertC2(uint256 c2) public pure override {
    require(c2 >= MIN_C2, "C2 too low");
    require(c2 <= MAX_C2, "C2 too high");
  }

  function assertY(uint256 y) public pure {
    require(y >= MIN_Y, "Y too low");
    require(y <= MAX_Y, "Y too high");
  }

  function assertAART(uint256 aart) public pure {
    require(aart >= MIN_AART, "AART too low");
    require(aart <= MAX_AART, "AART too high");
  }

  function assertAARS(uint256 aars) public pure {
    require(aars >= MIN_AARS, "AARS too low");
    require(aars <= MAX_AARS, "AARS too high");
  }

  function assertAARC(uint256 aarc) public pure {
    require(aarc >= MIN_AARC, "AARC too low");
    require(aarc <= MAX_AARC, "AARC too high");
  }

  function defaultBasisR() public view returns (uint256) {
    return _defaultBasisR;
  }

  function assertBasisR(uint256 basisR) public pure {
    require(basisR >= MIN_BASIS_R, "Basis r too low");
    require(basisR <= MAX_BASIS_R, "Basis r too high");
  }

  function defaultRateR() public view returns (uint256) {
    return _defaultRateR;
  }

  function assertRateR(uint256 rateR) public pure {
    require(rateR >= MIN_RATE_R, "Rate r too low");
    require(rateR <= MAX_RATE_R, "Rate r too high");
  }

  function defaultBasisR2() public view returns (uint256) {
    return _defaultBasisR2;
  }

  function assertBasisR2(uint256 basisR2) public pure {
    require(basisR2 >= MIN_BASIS_R2, "Basis R2 too low");
    require(basisR2 <= MAX_BASIS_R2, "Basis R2 too high");
  }

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setDefaultC1(uint256 newC1) external nonReentrant onlyProtocol {
    require(newC1 != _defaultC1, "Same redemption fee");
    assertC1(newC1);
    
    _defaultC1 = newC1;
    emit UpdateDefaultC1(_defaultC1, newC1);
  }

  function setDefaultC2(uint256 newC2) external nonReentrant onlyProtocol {
    require(newC2 != _defaultC2, "Same redemption fee");
    assertC2(newC2);
    
    _defaultC2 = newC2;
    emit UpdateDefaultC2(_defaultC2, newC2);
  }

  function setDefaultBasisR(uint256 newBasisR) external nonReentrant onlyProtocol {
    require(newBasisR != _defaultBasisR, "Same basis r");
    assertBasisR(newBasisR);
    
    _defaultBasisR = newBasisR;
    emit UpdateDefaultBasisR(_defaultBasisR, newBasisR);
  }

  function setDefaultRateR(uint256 newRateR) external nonReentrant onlyProtocol {
    require(newRateR != _defaultRateR, "Same rate r");
    assertRateR(newRateR);
    
    _defaultRateR = newRateR;
    emit UpdateDefaultRateR(_defaultRateR, newRateR);
  }

  function setDefaultBasisR2(uint256 newBasisR2) external nonReentrant onlyProtocol {
    require(newBasisR2 != _defaultBasisR2, "Same basis R2");
    assertBasisR2(newBasisR2);
    
    _defaultBasisR2 = newBasisR2;
    emit UpdateDefaultBasisR2(_defaultBasisR2, newBasisR2);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  /* =============== EVENTS ============= */

  event UpdateDefaultC1(uint256 prevDefaultC1, uint256 defaultC1);
  event UpdateDefaultC2(uint256 prevDeaultC2, uint256 defaultC2);
  event UpdateDefaultBasisR(uint256 prevDefaultBasisR, uint256 defaultBasisR);
  event UpdateDefaultRateR(uint256 prevDefaultRateR, uint256 defaultRateR);
  event UpdateDefaultBasisR2(uint256 prevDefaultBasisR2, uint256 defaultBasisR2);
}