// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "../interfaces/IProtocolSettings.sol";
import "../libs/Constants.sol";
import "../WandProtocol.sol";

contract ProtocolSettings is IProtocolSettings, Context, ReentrancyGuard {

  address public immutable wandProtocol;

  address internal _treasury;

  // Redemption fee rate with $USB. Default to 0.1%. [0, 10%]
  uint256 internal _defaultC1 = 1 * 10 ** 7;
  uint256 public constant MIN_C1 = 0;
  uint256 public constant MAX_C1 = 10 ** 9;

  // Redemption fee rate with X tokens paired with $USB. Default to 0.5%. [0, 10%]
  uint256 internal _defaultC2 = 5 * 10 ** 7;
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
  uint256 internal _defaultBasisR = 10 ** 9;
  uint256 public constant MIN_BASIS_R = 0;
  uint256 public constant MAX_BASIS_R = 10 ** 10;

  // Rate of r change per hour. Default to 0.001, [0, 1]
  uint256 internal _defaultRateR = 10 ** 7;
  uint256 public constant MIN_RATE_R = 0;
  uint256 public constant MAX_RATE_R = 10 ** 10;

  // Basis of R2. Default to 0.06, [0, 1]
  uint256 internal _defaultBasisR2 = 6 * 10 ** 8;
  uint256 public constant MIN_BASIS_R2 = 0;
  uint256 public constant MAX_BASIS_R2 = 10 ** 10;

  // Circuit breaker period. Default to 1 hour
  uint256 internal _defaultCiruitBreakPeriod = 1 hours;
  uint256 public constant MIN_CIRCUIT_BREAK_PERIOD = 1 minutes;
  uint256 public constant MAX_CIRCUIT_BREAK_PERIOD = 1 days;

  // X Tokens transfer fee. Default to 0.08%, [0, 100%]
  uint256 internal _defaultXTokensTransferFee = 8 * 10 ** 6;
  uint256 public constant MIN_X_TOKENS_TRANSFER_FEE = 0;
  uint256 public constant MAX_X_TOKENS_TRANSFER_FEE = 10 ** 10;

  constructor(address _wandProtocol, address _treasury_) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
    setTreasury(_treasury_);
  }

  /* ============== VIEWS =============== */

  function treasury() public view override returns (address) {
    return _treasury;
  }

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

  function defaultCiruitBreakPeriod() public view returns (uint256) {
    return _defaultCiruitBreakPeriod;
  }

  function assertCiruitBreakPeriod(uint256 circuitBreakPeriod) public pure {
    require(circuitBreakPeriod >= MIN_CIRCUIT_BREAK_PERIOD, "Circuit break period too short");
    require(circuitBreakPeriod <= MAX_CIRCUIT_BREAK_PERIOD, "Circuit break period too long");
  }

  function defaultXTokensTransferFee() public view returns (uint256) {
    return _defaultXTokensTransferFee;
  }

  function assertXTokensTransferFee(uint256 xTokensTransferFee) public pure {
    require(xTokensTransferFee >= MIN_X_TOKENS_TRANSFER_FEE, "X tokens transfer fee too low");
    require(xTokensTransferFee <= MAX_X_TOKENS_TRANSFER_FEE, "X tokens transfer fee too high");
  }

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setTreasury(address newTreasury) public nonReentrant onlyProtocol {
    require(newTreasury != address(0), "Zero address detected");
    require(newTreasury != _treasury, "Same _treasury");

    address prevTreasury = _treasury;
    _treasury = newTreasury;
    emit UpdateTreasury(prevTreasury, _treasury);
  }

  function setDefaultC1(uint256 newC1) external nonReentrant onlyProtocol {
    require(newC1 != _defaultC1, "Same redemption fee");
    assertC1(newC1);
    
    uint256 prevDefaultC1 = _defaultC1;
    _defaultC1 = newC1;
    emit UpdateDefaultC1(prevDefaultC1, _defaultC1);
  }

  function setDefaultC2(uint256 newC2) external nonReentrant onlyProtocol {
    require(newC2 != _defaultC2, "Same redemption fee");
    assertC2(newC2);
    
    uint256 prevDefaultC2 = _defaultC2;
    _defaultC2 = newC2;
    emit UpdateDefaultC2(prevDefaultC2, _defaultC2);
  }

  function setDefaultBasisR(uint256 newBasisR) external nonReentrant onlyProtocol {
    require(newBasisR != _defaultBasisR, "Same basis r");
    assertBasisR(newBasisR);
    
    uint256 prevDefaultBasisR = _defaultBasisR;
    _defaultBasisR = newBasisR;
    emit UpdateDefaultBasisR(prevDefaultBasisR, _defaultBasisR);
  }

  function setDefaultRateR(uint256 newRateR) external nonReentrant onlyProtocol {
    require(newRateR != _defaultRateR, "Same rate r");
    assertRateR(newRateR);
    
    uint256 prevDefaultRateR = _defaultRateR;
    _defaultRateR = newRateR;
    emit UpdateDefaultRateR(prevDefaultRateR, _defaultRateR);
  }

  function setDefaultBasisR2(uint256 newBasisR2) external nonReentrant onlyProtocol {
    require(newBasisR2 != _defaultBasisR2, "Same basis R2");
    assertBasisR2(newBasisR2);
    
    uint256 prevDefaultBasisR2 = _defaultBasisR2;
    _defaultBasisR2 = newBasisR2;
    emit UpdateDefaultBasisR2(prevDefaultBasisR2, _defaultBasisR2);
  }

  function setDefaultCiruitBreakPeriod(uint256 newDefaultCircuitBreakPeriod) external nonReentrant onlyProtocol {
    require(newDefaultCircuitBreakPeriod != _defaultCiruitBreakPeriod, "Same default circuit break period");
    assertCiruitBreakPeriod(newDefaultCircuitBreakPeriod);
    
    uint256 prevDefaultCiruitBreakPeriod = _defaultCiruitBreakPeriod;
    _defaultCiruitBreakPeriod = newDefaultCircuitBreakPeriod;
    emit UpdateDefaultCircuitBreakPeriod(prevDefaultCiruitBreakPeriod, _defaultCiruitBreakPeriod);
  }

  function setDefaultXTokensTransferFee(uint256 newDefaultXTokensTransferFee) external nonReentrant onlyProtocol {
    require(newDefaultXTokensTransferFee != _defaultXTokensTransferFee, "Same default X tokens transfer fee");
    assertXTokensTransferFee(newDefaultXTokensTransferFee);
    
    uint256 prevDefaultXTokensTransferFee = _defaultXTokensTransferFee;
    _defaultXTokensTransferFee = newDefaultXTokensTransferFee;
    emit UpdateDefaultXTokensTransferFee(prevDefaultXTokensTransferFee, _defaultXTokensTransferFee);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  /* =============== EVENTS ============= */

  event UpdateTreasury(address prevTreasury, address newTreasury);
  event UpdateDefaultC1(uint256 prevDefaultC1, uint256 defaultC1);
  event UpdateDefaultC2(uint256 prevDeaultC2, uint256 defaultC2);
  event UpdateDefaultBasisR(uint256 prevDefaultBasisR, uint256 defaultBasisR);
  event UpdateDefaultRateR(uint256 prevDefaultRateR, uint256 defaultRateR);
  event UpdateDefaultBasisR2(uint256 prevDefaultBasisR2, uint256 defaultBasisR2);
  event UpdateDefaultCircuitBreakPeriod(uint256 prevDefaultCircuitBreakPeriod, uint256 circuitDefaultBreakPeriod);
  event UpdateDefaultXTokensTransferFee(uint256 prevDefaultXTokensTransferFee, uint256 defaultXTokensTransferFee);
}