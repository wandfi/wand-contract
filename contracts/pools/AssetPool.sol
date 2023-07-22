// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IWandProtocol.sol";
import "../interfaces/IAssetPool.sol";
import "../interfaces/IAssetPoolCalculaor.sol";
import "../interfaces/IInterestPoolFactory.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IUSB.sol";
import "../interfaces/IAssetX.sol";
import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";

contract AssetPool is IAssetPool, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  IWandProtocol public immutable wandProtocol;
  IProtocolSettings public immutable settings;
  address public immutable assetPoolCalculator;
  address public immutable assetToken;
  address public immutable assetTokenPriceFeed;
  address public immutable usbToken;
  address public immutable xToken;

  uint256 internal immutable settingsDecimals;
  EnumerableSet.Bytes32Set internal _assetPoolParamsSet;
  mapping(bytes32 => uint256) internal _assetPoolParams;

  uint256 internal _usbTotalSupply;

  uint256 internal _lastInterestSettlementTime;
  uint256 internal _undistributedInterest;

  uint256 internal _aarBelowSafeLineTime;
  uint256 internal _aarBelowCircuitBreakerLineTime;

  constructor(
    address _wandProtocol,
    address _assetToken,
    address _assetTokenPriceFeed,
    address _xToken,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  )  {
    require(
      _wandProtocol != address(0) && _assetToken != address(0) && _assetTokenPriceFeed != address(0) && _xToken != address(0), 
      "Zero address detected"
    );
    require(assetPoolParams.length == assetPoolParamsValues.length, "Invalid params length");

    wandProtocol = IWandProtocol(_wandProtocol);
    assetToken = _assetToken;
    assetTokenPriceFeed = _assetTokenPriceFeed;
    xToken = _xToken;
    assetPoolCalculator = wandProtocol.assetPoolCalculator();
    usbToken = wandProtocol.usbToken();

    settings = IProtocolSettings(IWandProtocol(_wandProtocol).settings());
    settingsDecimals = settings.decimals();

    for (uint256 i = 0; i < assetPoolParams.length; i++) {
      _updateParam(assetPoolParams[i], assetPoolParamsValues[i]);
    }
  }

  /* ================= VIEWS ================ */

  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() public view returns (uint256) {
    return _usbTotalSupply;
  }

  function getAssetTotalAmount() public view returns (uint256) {
    return _getAssetTotalAmount();
  }

  function getAssetTokenPrice() public view returns (uint256, uint256) {
    uint256 price = IPriceFeed(assetTokenPriceFeed).latestPrice();
    uint256 priceDecimals = IPriceFeed(assetTokenPriceFeed).decimals();

    return (price, priceDecimals);
  }

  /**
   * @notice Current adequency ratio of the pool
   * @dev AAReth = (M_ETH * P_ETH / Musb-eth) * 100%
   */
  function AAR() public view returns (uint256) {
    return IAssetPoolCalculaor(assetPoolCalculator).AAR(IAssetPool(this));
  }

  function AARDecimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function pairedUSBAmountToRedeemByXTokens(uint256 xTokenAmount) public view returns (uint256) {
    return IAssetPoolCalculaor(assetPoolCalculator).pairedUSBAmountToRedeemByXTokens(IAssetPool(this), xTokenAmount);
  }

  function calculateUSBToXTokensOut(address account, uint256 usbAmount) public view returns (uint256) {
    uint256 aar = AAR();
    uint256 AARC = _assetPoolParamValue("AARC");
    uint256 CircuitBreakPeriod = _assetPoolParamValue("CircuitBreakPeriod");
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= CircuitBreakPeriod), "Circuit breaker AAR reached");

    Constants.AssetPoolState memory S = _getAssetPoolState();

    return IAssetPoolCalculaor(assetPoolCalculator).calculateUSBToXTokensOut(S, account, usbAmount);
  }

  function calculateMintUSBOut(uint256 assetAmount) public view returns (uint256) {
    Constants.AssetPoolState memory S = _getAssetPoolState();
    return IAssetPoolCalculaor(assetPoolCalculator).calculateMintUSBOut(S, assetAmount);
  }

  function _getAssetPoolState() internal view returns (Constants.AssetPoolState memory) {
    Constants.AssetPoolState memory S;
    S.M_ETH = _getAssetTotalAmount();
    S.P_ETH = IPriceFeed(assetTokenPriceFeed).latestPrice();
    S.P_ETH_DECIMALS = IPriceFeed(assetTokenPriceFeed).decimals();
    S.M_USB_ETH = _usbTotalSupply;
    S.M_ETHx = IERC20(xToken).totalSupply();
    S.aar = AAR();
    S.AART = _assetPoolParamValue("AART");
    S.AARS = _assetPoolParamValue("AARS");
    S.AARC = _assetPoolParamValue("AARC");
    S.AARDecimals = AARDecimals();
    S.RateR = _assetPoolParamValue("RateR");
    S.BasisR = _assetPoolParamValue("BasisR");
    S.BasisR2 = _assetPoolParamValue("BasisR2");

    return S;
  }

  function calculateMintXTokensOut(uint256 assetAmount) public view returns (uint256) {
    uint256 aar = AAR();
    // console.log('calculateMintXTokensOut, msg.value: %s', msg.value);
    uint256 AARC = _assetPoolParamValue("AARC");
    uint256 CircuitBreakPeriod = _assetPoolParamValue("CircuitBreakPeriod");
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= CircuitBreakPeriod), "AAR Below Circuit Breaker AAR Threshold");

    return IAssetPoolCalculaor(assetPoolCalculator).calculateMintXTokensOut(IAssetPool(this), assetAmount);
  }

  function calculateInterest() public view returns (uint256, uint256) {
    uint256 newInterestAmount = 0;
    uint256 totalInterestAmount = newInterestAmount.add(_undistributedInterest);

    if (_lastInterestSettlementTime == 0) {
      return (newInterestAmount, totalInterestAmount);
    }

    // ∆ethx = (t / 365 days) * Y * M_ETHx
    uint256 timeElapsed = block.timestamp.sub(_lastInterestSettlementTime);
    uint256 xTokenTotalAmount = IAssetX(xToken).totalSupply();
    uint256 Y = _assetPoolParamValue("Y");
    newInterestAmount = timeElapsed.mul(Y).mul(xTokenTotalAmount).div(365 days).div(10 ** settingsDecimals);
    totalInterestAmount = newInterestAmount.add(_undistributedInterest);

    return (newInterestAmount, totalInterestAmount);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * @notice Mint $USB tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintUSB(uint256 assetAmount) external payable override nonReentrant doCheckAAR doSettleInterest {
    uint256 usbOutAmount = calculateMintUSBOut(assetAmount);

    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);
    IUSB(usbToken).mint(_msgSender(), usbOutAmount);
    _usbTotalSupply = _usbTotalSupply.add(usbOutAmount);

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = getAssetTokenPrice();
    emit USBMinted(_msgSender(), assetAmount, usbOutAmount, assetTokenPrice, assetTokenPriceDecimals);
  }

  /**
   * @notice Mint X tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintXTokens(uint256 assetAmount) external payable override nonReentrant doCheckAAR doSettleInterest {
    uint256 xTokenAmount = calculateMintXTokensOut(assetAmount);
    // console.log('mintXTokens, x token out: %s', xTokenAmount);

    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);
    IAssetX(xToken).mint(_msgSender(), xTokenAmount);
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = getAssetTokenPrice();
    emit XTokenMinted(_msgSender(), assetAmount, xTokenAmount, assetTokenPrice, assetTokenPriceDecimals);
  }

  /**
   * @notice Redeem asset tokens with $USB
   * @param usbAmount: Amount of $USB tokens used to redeem for asset tokens
   */
  function redeemByUSB(uint256 usbAmount) external override nonReentrant doCheckAAR doSettleInterest {
    require(usbAmount > 0, "Amount must be greater than 0");

    uint256 assetAmount = 0;

    uint256 aar = _AAR();
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = getAssetTokenPrice();

    // if AAR >= 100%,  Δeth = (Δusb / P_ETH) * (1 -C1)
    uint256 fee = 0;
    if (aar >= 10 ** AARDecimals()) {
      uint256 total = usbAmount.mul(10 ** assetTokenPriceDecimals).div(assetTokenPrice);
      // C1 only takes effect when AAR >= [2 * (AART - 100%) + 100%]
      uint256 AART = _assetPoolParamValue("AART");
      uint256 C1 = _assetPoolParamValue("C1");
      if (aar >= AART.sub(10 ** AARDecimals()).mul(2).add(10 ** AARDecimals())) {
        fee = total.mul(C1).div(10 ** settingsDecimals);
      }
      assetAmount = total.sub(fee);
    }
    // else if AAR < 100%, Δeth = (Δusb * M_ETH) / Musb-eth
    else {
      uint256 assetTotalAmount = _getAssetTotalAmount();
      assetAmount = usbAmount.mul(assetTotalAmount).div(_usbTotalSupply);
    }

    IUSB(usbToken).burn(_msgSender(), usbAmount);
    _usbTotalSupply = _usbTotalSupply.sub(usbAmount);

    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);
    emit AssetRedeemedWithUSB(_msgSender(), usbAmount, assetAmount, assetTokenPrice, assetTokenPriceDecimals);

    if (fee > 0) {
      address treasury = settings.treasury();
      TokensTransfer.transferTokens(assetToken, address(this), treasury, fee);
      emit AssetRedeemedWithUSBFeeCollected(_msgSender(), treasury, usbAmount, fee, assetTokenPrice, assetTokenPriceDecimals);
    }
  }

  /**
   * @notice Redeem asset tokens with X tokens
   * @param xTokenAmount: Amount of X tokens used to redeem for asset tokens
   */
  function redeemByXTokens(uint256 xTokenAmount) external override nonReentrant doCheckAAR doSettleInterest {
    uint256 pairedUSBAmount = pairedUSBAmountToRedeemByXTokens(xTokenAmount);

    // Δeth = Δethx * M_ETH / M_ETHx * (1 -C2)
    uint256 C2 = _assetPoolParamValue("C2");
    uint256 total = xTokenAmount.mul(_getAssetTotalAmount()).div(IAssetX(xToken).totalSupply());
    uint256 fee = total.mul(C2).div(10 ** settingsDecimals);
    uint256 assetAmount = total.sub(fee);

    IUSB(usbToken).burn(_msgSender(), pairedUSBAmount);
    _usbTotalSupply = _usbTotalSupply.sub(pairedUSBAmount);
    IAssetX(xToken).burn(_msgSender(), xTokenAmount);

    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = getAssetTokenPrice();
    emit AssetRedeemedWithXTokens(_msgSender(), xTokenAmount, pairedUSBAmount, assetAmount, assetTokenPrice, assetTokenPriceDecimals);

    if (fee > 0) {
      address treasury = settings.treasury();
      TokensTransfer.transferTokens(assetToken, address(this), treasury, fee);
      emit AssetRedeemedWithXTokensFeeCollected(_msgSender(), treasury, xTokenAmount, fee, pairedUSBAmount, assetAmount, assetTokenPrice, assetTokenPriceDecimals);
    }
  }

  function usbToXTokens(uint256 usbAmount) external override nonReentrant doCheckAAR doSettleInterest {  
    uint256 xTokenOut = calculateUSBToXTokensOut(_msgSender(), usbAmount);

    IUSB(usbToken).burn(_msgSender(), usbAmount);
    _usbTotalSupply = _usbTotalSupply.sub(usbAmount);
    IAssetX(xToken).mint(_msgSender(), xTokenOut);

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = getAssetTokenPrice();
    emit UsbToXTokens(_msgSender(), usbAmount, xTokenOut, assetTokenPrice, assetTokenPriceDecimals);
  }

  function checkAAR() external override nonReentrant doCheckAAR {
    _AAR();
  }

  function settleInterest() external override nonReentrant doCheckAAR doSettleInterest {
    // Nothing to do here
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function updateParam(bytes32 param, uint256 value) external nonReentrant onlyOwner {
    _updateParam(param, value);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _updateParam(bytes32 param, uint256 value) internal {
    require(settings.isValidParam(param, value), "Invalid param or value");

    _assetPoolParamsSet.add(param);
    _assetPoolParams[param] = value;
    emit UpdateParamValue(param, value);
  }

  function _assetPoolParamValue(bytes32 param) internal view returns (uint256) {
    require(param.length > 0, "Empty param name");

    if (_assetPoolParamsSet.contains(param)) {
      return _assetPoolParams[param];
    }
    return settings.paramDefaultValue(param);
  }

  function _AAR() internal returns (uint256) {
    uint256 aar = AAR();

    uint256 AARS = _assetPoolParamValue("AARS");
    uint256 AARC = _assetPoolParamValue("AARC");
    if (_aarBelowSafeLineTime == 0) {
      if (aar < AARS) {
        _aarBelowSafeLineTime = block.timestamp;
      }
    } else if (aar >= AARS) {
      _aarBelowSafeLineTime = 0;
    }

    // console.log('_AAR, _aarBelowCircuitBreakerLineTime: %s, aar: %s', _aarBelowCircuitBreakerLineTime, aar);
    if (_aarBelowCircuitBreakerLineTime == 0) {
      if (aar < AARC) {
        _aarBelowCircuitBreakerLineTime = block.timestamp;
      }
    } else if (aar >= AARC) {
      _aarBelowCircuitBreakerLineTime = 0;
    }
    // console.log('_AAR after, _aarBelowCircuitBreakerLineTime: %s', _aarBelowCircuitBreakerLineTime);

    return aar;
  }

  function _getAssetTotalAmount() internal view returns (uint256) {
    // console.log('_getAssetTotalAmount, msg.value: %s', msg.value);

    if (assetToken == Constants.NATIVE_TOKEN) {
      return address(this).balance.sub(msg.value);
    }
    else {
      return IERC20(assetToken).balanceOf(address(this));
    }
  }

  function _settleInterest() internal {
    (uint256 newInterestAmount, uint256 totalInterestAmount) = calculateInterest();
    if (newInterestAmount > 0) {
      IAssetX(xToken).mint(address(this), newInterestAmount);
    }
    // console.log('_settleInterest, new interest: %s, total: %s', newInterestAmount, totalInterestAmount);

    if (totalInterestAmount > 0) {
      IInterestPoolFactory interestPoolFactory = IInterestPoolFactory(wandProtocol.interestPoolFactory());
      IAssetX(xToken).approve(address(interestPoolFactory), totalInterestAmount);
      bool distributed = interestPoolFactory.distributeInterestRewards(xToken, totalInterestAmount);
      emit InterestSettlement(totalInterestAmount, distributed);

      if (distributed) {
        _undistributedInterest = 0;
      }
      else {
        _undistributedInterest = totalInterestAmount;
      }
    }
  }

  /**
   * @notice Interest generation starts when both $USB and X tokens are minted
   */
  function _startOrPauseInterestGeneration() internal {
    if (_usbTotalSupply > 0 && IAssetX(xToken).totalSupply() > 0) {
      _lastInterestSettlementTime = block.timestamp;
    }
    else {
      _lastInterestSettlementTime = 0;
    }
  }

  /* ============== MODIFIERS =============== */

  modifier onlyOwner() {
    require(_msgSender() == wandProtocol.protocolOwner(), "Caller is not owner");
    _;
  }

  modifier doSettleInterest() {
    _settleInterest();
    _;
    _startOrPauseInterestGeneration();
  }

  modifier doCheckAAR() {
    _AAR(); // update _aarBelowSafeLineTime and _aarBelowCircuitBreakerLineTime
    _;
  }

  /* =============== EVENTS ============= */

  event UpdateParamValue(bytes32 indexed param, uint256 value);
  
  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 usbTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSBFeeCollected(address indexed user, address indexed feeTo, uint256 usbTokenAmount, uint256 feeAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokens(address indexed user, uint256 xTokenAmount, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokensFeeCollected(address indexed user, address indexed feeTo, uint256 xTokenAmount, uint256 fee, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event UsbToXTokens(address indexed user, uint256 usbAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);

  event InterestSettlement(uint256 interestAmount, bool distributed);
}