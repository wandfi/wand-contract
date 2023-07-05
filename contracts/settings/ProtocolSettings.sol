// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "../WandProtocol.sol";
import "../interfaces/IProtocolSettings.sol";

contract ProtocolSettings is IProtocolSettings, Context, ReentrancyGuard {

  address public immutable wandProtocol;

  uint256 public constant DECIMALS_DENOMINATOR = 10 ** 10;

  // Default to 0.3%. [0.1%, 1%]
  uint256 private _redemptionFeeWithUSBTokens = 3 * 10 ** 7;
  uint256 public constant MIN_REDEMPTION_FEE_WITH_USB_TOKENS = 10 ** 7;
  uint256 public constant MAX_REDEMPTION_FEE_WITH_USB_TOKENS = 10 ** 8;

  // Default to 0.3%. [0.1%, 1%]
  uint256 private _redemptionFeeWithXTokens = 3 * 10 ** 7;
  uint256 public constant MIN_REDEMPTION_FEE_WITH_X_TOKENS = 10 ** 7;
  uint256 public constant MAX_REDEMPTION_FEE_WITH_X_TOKENS = 10 ** 8;

  constructor(address _wandProtocol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
  }

  /* ============== VIEWS =============== */

  function redemptionFeeWithUSBTokens() public view returns (uint256) {
    return _redemptionFeeWithUSBTokens;
  }

  function redemptionFeeWithXTokens() public view returns (uint256) {
    return _redemptionFeeWithXTokens;
  }


  /* ============ MUTATIVE FUNCTIONS =========== */

  function setRedemptionFeeWithUSBTokens(uint256 newRedemptionFeeWithUSBTokens) external nonReentrant onlyProtocol {
    require(newRedemptionFeeWithUSBTokens != _redemptionFeeWithUSBTokens, "Same redemption fee");
    require(newRedemptionFeeWithUSBTokens >= MIN_REDEMPTION_FEE_WITH_USB_TOKENS, "Redemption fee too low");
    require(newRedemptionFeeWithUSBTokens <= MAX_REDEMPTION_FEE_WITH_USB_TOKENS, "Redemption fee too high");
    
    _redemptionFeeWithUSBTokens = newRedemptionFeeWithUSBTokens;
    emit RedemptionFeeWithUSBTokensUpdated(_redemptionFeeWithUSBTokens, newRedemptionFeeWithUSBTokens);
  }

  function setRedemptionFeeWithXTokens(uint256 newRedemptionFeeWithXTokens) external nonReentrant onlyProtocol {
    require(newRedemptionFeeWithXTokens != _redemptionFeeWithXTokens, "Same redemption fee");
    require(newRedemptionFeeWithXTokens >= MIN_REDEMPTION_FEE_WITH_X_TOKENS, "Redemption fee too low");
    require(newRedemptionFeeWithXTokens <= MAX_REDEMPTION_FEE_WITH_X_TOKENS, "Redemption fee too high");
    
    _redemptionFeeWithXTokens = newRedemptionFeeWithXTokens;
    emit RedemptionFeeWithXTokensUpdated(_redemptionFeeWithXTokens, newRedemptionFeeWithXTokens);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  /* =============== EVENTS ============= */

  event RedemptionFeeWithUSBTokensUpdated(uint256 prevRedemptionFeeWithUSBTokens, uint256 newRedemptionFeeWithUSBTokens);

  event RedemptionFeeWithXTokensUpdated(uint256 prevRedemptionFeeWithXTokens, uint256 newRedemptionFeeWithXTokens);

}