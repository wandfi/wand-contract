// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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
// import "../tokens/AssetX.sol";

contract AssetPool is IAssetPool, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  IWandProtocol public immutable wandProtocol;
  IProtocolSettings public immutable settings;
  // address public immutable assetPoolFactory;
  address public immutable assetPoolCalculator;
  address public immutable assetToken;
  address public immutable assetTokenPriceFeed;
  address public immutable usbToken;
  address public immutable xToken;

  uint256 internal immutable settingsDecimals;

  uint256 internal _usbTotalSupply;

  uint256 internal _lastInterestSettlementTime;
  uint256 internal _undistributedInterest;

  uint256 internal _aarBelowSafeLineTime;
  uint256 internal _aarBelowCircuitBreakerLineTime;

  // uint256 public C1;
  // uint256 public C2;
  // uint256 public Y;
  // uint256 public AART;
  // uint256 public AARS;
  // uint256 public AARC;
  // uint256 public BasisR;
  // uint256 public RateR;
  // uint256 public BasisR2;
  // uint256 public CiruitBreakPeriod;

  // new AssetPool(wandProtocol, assetToken, assetPriceFeed, xToken, assetPoolParams, assetPoolParamsValues));
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
      settings.updateAssetPoolParam(address(this), assetPoolParams[i], assetPoolParamsValues[i]);
    }

    // C1 = settings.defaultC1();
    // C2 = settings.defaultC2();

    // settings.assertY(_Y_);
    // Y = _Y_;

    // settings.assertAART(_AART_);
    // AART = _AART_;
    // settings.assertAARS(_AARS_);
    // AARS = _AARS_;
    // settings.assertAARC(_AARC_);
    // AARC = _AARC_;

    // BasisR = settings.defaultBasisR();
    // BasisR2 = settings.defaultBasisR2();
    // RateR = settings.defaultRateR();
    // CiruitBreakPeriod = settings.defaultCiruitBreakPeriod();
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

  // function xToken() public view returns (address) {
  //   return xToken;
  // }

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
    uint256 AARC = settings.assetPoolParamValue(address(this), "AARC");
    uint256 CiruitBreakPeriod = settings.assetPoolParamValue(address(this), "CiruitBreakPeriod");
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= CiruitBreakPeriod), "Circuit breaker AAR reached");

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
    S.AART = settings.assetPoolParamValue(address(this), "AART");
    S.AARS = settings.assetPoolParamValue(address(this), "AARS");
    S.AARC = settings.assetPoolParamValue(address(this), "AARC");
    S.AARDecimals = AARDecimals();
    S.RateR = settings.assetPoolParamValue(address(this), "RateR");
    S.BasisR = settings.assetPoolParamValue(address(this), "BasisR");
    S.BasisR2 = settings.assetPoolParamValue(address(this), "BasisR2");

    return S;
  }

  function calculateMintXTokensOut(uint256 assetAmount) public view returns (uint256) {
    uint256 aar = AAR();
    uint256 AARC = settings.assetPoolParamValue(address(this), "AARC");
    uint256 CiruitBreakPeriod = settings.assetPoolParamValue(address(this), "CiruitBreakPeriod");
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= CiruitBreakPeriod), "AAR Below Circuit Breaker AAR Threshold");

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
    uint256 Y = settings.assetPoolParamValue(address(this), "Y");
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
      uint256 AART = settings.assetPoolParamValue(address(this), "AART");
      uint256 C1 = settings.assetPoolParamValue(address(this), "C1");
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
    uint256 C2 = settings.assetPoolParamValue(address(this), "C2");
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

  // function setXToken(address _xToken_) external nonReentrant onlyOwner {
  //   require(_xToken_ != address(0), "Zero address detected");
  //   xToken = _xToken_;
  // }

  // function setC1(uint256 newC1) external nonReentrant onlyOwner {
  //   require(newC1 != C1, "Same redemption fee");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertC1(newC1);
    
  //   uint256 prevC1 = C1;
  //   C1 = newC1;
  //   emit UpdatedC1(prevC1, C1);
  // }

  // function setC2(uint256 newC2) external nonReentrant onlyOwner {
  //   require(newC2 != C2, "Same redemption fee");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertC2(newC2);

  //   uint256 prevC2 = C2;
  //   C2 = newC2;
  //   emit UpdatedC2(prevC2, C2);
  // }

  // function setY(uint256 newY) external nonReentrant onlyOwner {
  //   require(newY != Y, "Same yield rate");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertY(newY);

  //   uint256 prevY = Y;
  //   Y = newY;
  //   emit UpdatedY(prevY, Y);
  // }

  // function setBasisR(uint256 newBasisR) external nonReentrant onlyOwner {
  //   require(newBasisR != BasisR, "Same basis of r");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertBasisR(newBasisR);

  //   uint256 prevBasisR = BasisR;
  //   BasisR = newBasisR;
  //   emit UpdatedBasisR(prevBasisR, BasisR);
  // }

  // function setRateR(uint256 newRateR) external nonReentrant onlyOwner {
  //   require(newRateR != RateR, "Same rate of r");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertRateR(newRateR);

  //   uint256 prevRateR = RateR;
  //   RateR = newRateR;
  //   emit UpdatedRateR(prevRateR, RateR);
  // }

  // function setBasisR2(uint256 newBasisR2) external nonReentrant onlyOwner {
  //   require(newBasisR2 != BasisR2, "Same basis of R2");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertBasisR2(newBasisR2);

  //   uint256 prevBasisR2 = BasisR2;
  //   BasisR2 = newBasisR2;
  //   emit UpdatedBasisR2(prevBasisR2, BasisR2);
  // }

  // function setCiruitBreakPeriod(uint256 newCiruitBreakPeriod) external nonReentrant onlyOwner {
  //   require(newCiruitBreakPeriod != CiruitBreakPeriod, "Same circuit breaker period");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertCiruitBreakPeriod(newCiruitBreakPeriod);

  //   uint256 prevCiruitBreakPeriod = CiruitBreakPeriod;
  //   CiruitBreakPeriod = newCiruitBreakPeriod;
  //   emit UpdateCiruitBreakPeriod(prevCiruitBreakPeriod, CiruitBreakPeriod);
  // }

  // function setAART(uint256 newAART) external nonReentrant onlyOwner {
  //   require(newAART != AART, "Same target AAR");
  //   require(newAART >= AARS, "Target AAR must be greater than or equal to safe AAR");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertAART(newAART);

  //   uint256 prevAART = AART;
  //   AART = newAART;
  //   emit UpdatedAART(prevAART, AART);
  // }

  // function setAARS(uint256 newAARS) external nonReentrant onlyOwner {
  //   require(newAARS != AARS, "Same safe AAR");
  //   require(newAARS <= AART, "Safe AAR must be less than or equal to target AAR");
  //   require(newAARS >= AARC, "Safe AAR must be greater than or equal to circuit breaker AAR");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertAARS(newAARS);

  //   uint256 prevAARS = AARS;
  //   AARS = newAARS;
  //   emit UpdatedAARS(prevAARS, AARS);
  // }

  // function setAARC(uint256 newAARC) external nonReentrant onlyOwner {
  //   require(newAARC != AARC, "Same circuit breaker AAR");
  //   require(newAARC <= AARS, "Circuit breaker AAR must be less than or equal to safe AAR");

  //   IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
  //   settings.assertAARC(newAARC);

  //   uint256 prevAARC = AARC;
  //   AARC = newAARC;
  //   emit UpdatedAARC(prevAARC, AARC);
  // }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _AAR() internal returns (uint256) {
    uint256 aar = AAR();

    uint256 AARS = settings.assetPoolParamValue(address(this), "AARS");
    uint256 AARC = settings.assetPoolParamValue(address(this), "AARC");
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

  // event UpdatedC1(uint256 prevC1, uint256 newC1);
  // event UpdatedC2(uint256 prevC2, uint256 newC2);
  // event UpdatedY(uint256 prevY, uint256 newY);
  // event UpdatedAART(uint256 prevAART, uint256 newAART);
  // event UpdatedAARS(uint256 prevAARS, uint256 newAARS);
  // event UpdatedAARC(uint256 prevAARC, uint256 newAARC);
  // event UpdatedBasisR(uint256 prevBasisR, uint256 newBasisR);
  // event UpdatedRateR(uint256 prevRateR, uint256 newRateR);
  // event UpdatedBasisR2(uint256 prevBasisR2, uint256 newBasisR2);
  // event UpdateCiruitBreakPeriod(uint256 prevCiruitBreakPeriod, uint256 newCiruitBreakPeriod);

  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 usbTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSBFeeCollected(address indexed user, address indexed feeTo, uint256 usbTokenAmount, uint256 feeAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokens(address indexed user, uint256 xTokenAmount, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokensFeeCollected(address indexed user, address indexed feeTo, uint256 xTokenAmount, uint256 fee, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event UsbToXTokens(address indexed user, uint256 usbAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);

  event InterestSettlement(uint256 interestAmount, bool distributed);
}