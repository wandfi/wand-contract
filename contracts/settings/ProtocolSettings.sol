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

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  /* =============== EVENTS ============= */

  event UpdateDefaultC1(uint256 prevDefaultC1, uint256 defaultC1);
  event UpdateDefaultC2(uint256 prevDeaultC2, uint256 defaultC2);
}