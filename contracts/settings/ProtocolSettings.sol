// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "../WandProtocol.sol";
import "../interfaces/IProtocolSettings.sol";
import "../libs/Constants.sol";

contract ProtocolSettings is IProtocolSettings, Context, ReentrancyGuard {

  address public immutable wandProtocol;

  // Default to 0.3%. [0.1%, 1%]
  uint256 private _defaultRedemptionFeeWithUSBTokens = 3 * 10 ** 7;
  uint256 public constant MIN_REDEMPTION_FEE_WITH_USB_TOKENS = 10 ** 7;
  uint256 public constant MAX_REDEMPTION_FEE_WITH_USB_TOKENS = 10 ** 8;

  // Default to 0.3%. [0.1%, 1%]
  uint256 private _defaultRedemptionFeeWithXTokens = 3 * 10 ** 7;
  uint256 public constant MIN_REDEMPTION_FEE_WITH_X_TOKENS = 10 ** 7;
  uint256 public constant MAX_REDEMPTION_FEE_WITH_X_TOKENS = 10 ** 8;

  constructor(address _wandProtocol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
  }

  /* ============== VIEWS =============== */

  function settingDecimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function defaultRedemptionFeeWithUSBTokens() public view returns (uint256) {
    return _defaultRedemptionFeeWithUSBTokens;
  }

  function defaultRedemptionFeeWithXTokens() public view returns (uint256) {
    return _defaultRedemptionFeeWithXTokens;
  }

  function assertRedemptionFeeWithUSBTokens(uint256 redemptionFeeWithUSBTokens) external view override {
    require(redemptionFeeWithUSBTokens >= MIN_REDEMPTION_FEE_WITH_USB_TOKENS, "Redemption fee too low");
    require(redemptionFeeWithUSBTokens <= MAX_REDEMPTION_FEE_WITH_USB_TOKENS, "Redemption fee too high");
  }

  function assertRedemptionFeeWithXTokens(uint256 redemptionFeeWithXTokens) external view override {
    require(redemptionFeeWithXTokens >= MIN_REDEMPTION_FEE_WITH_X_TOKENS, "Redemption fee too low");
    require(redemptionFeeWithXTokens <= MAX_REDEMPTION_FEE_WITH_X_TOKENS, "Redemption fee too high");
  }


  /* ============ MUTATIVE FUNCTIONS =========== */

  function setDefaultRedemptionFeeWithUSBTokens(uint256 newDefaultRedemptionFeeWithUSBTokens) external nonReentrant onlyProtocol {
    require(newDefaultRedemptionFeeWithUSBTokens != _defaultRedemptionFeeWithUSBTokens, "Same redemption fee");
    assertRedemptionFeeWithUSBTokens(newDefaultRedemptionFeeWithUSBTokens);
    
    _defaultRedemptionFeeWithUSBTokens = newDefaultRedemptionFeeWithUSBTokens;
    emit DefaultRedemptionFeeWithUSBTokensUpdated(_defaultRedemptionFeeWithUSBTokens, newDefaultRedemptionFeeWithUSBTokens);
  }

  function setDefaultRedemptionFeeWithXTokens(uint256 newDefaultRedemptionFeeWithXTokens) external nonReentrant onlyProtocol {
    require(newDefaultRedemptionFeeWithXTokens != _defaultRedemptionFeeWithXTokens, "Same redemption fee");
    assertRedemptionFeeWithXTokens(newDefaultRedemptionFeeWithXTokens);
    
    _defaultRedemptionFeeWithXTokens = newDefaultRedemptionFeeWithXTokens;
    emit DefaultRedemptionFeeWithXTokensUpdated(_defaultRedemptionFeeWithXTokens, newDefaultRedemptionFeeWithXTokens);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  /* =============== EVENTS ============= */

  event DefaultRedemptionFeeWithUSBTokensUpdated(uint256 prevRedemptionFeeWithUSBTokens, uint256 newDefaultRedemptionFeeWithUSBTokens);

  event DefaultRedemptionFeeWithXTokensUpdated(uint256 prevRedemptionFeeWithXTokens, uint256 newDefaultRedemptionFeeWithXTokens);

}