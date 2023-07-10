// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IAssetPool.sol";
import "../interfaces/IInterestPoolFactory.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IProtocolSettings.sol";
import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";
import "../tokens/AssetX.sol";
import "../tokens/USB.sol";

contract AssetPool is IAssetPool, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public immutable wandProtocol;
  address public immutable assetPoolFactory;
  address public immutable assetToken;
  address public immutable assetTokenPriceFeed;
  address public immutable usbToken;
  address public immutable xToken;

  uint256 internal _usbTotalSupply;

  uint256 internal immutable _settingsDecimals;

  uint256 internal _lastInterestSettlementTime;

  uint256 internal _aarBelowSafeThresholdTime;
  uint256 internal _aarBelowCircuitBreakerThresholdTime;

  uint256 public C1;
  uint256 public C2;
  uint256 public Y;
  uint256 public AART;
  uint256 public AARS;
  uint256 public AARC;
  uint256 public BasisR;
  uint256 public RateR;
  uint256 public BasisR2;
  uint256 public CiruitBreakPeriod;

  constructor(
    address _wandProtocol,
    address _assetPoolFactory,
    address _assetToken,
    address _assetTokenPriceFeed,
    address _usbToken,
    string memory _xTokenName,
    string memory _xTokenSymbol,
    uint256 _Y,
    uint256 _AART,
    uint256 _AARS,
    uint256 _AARC
  ) {
    require(_wandProtocol != address(0), "Zero address detected");
    require(_assetPoolFactory != address(0), "Zero address detected");
    require(_assetToken != address(0), "Zero address detected");
    require(_assetTokenPriceFeed != address(0), "Zero address detected");
    require(_usbToken != address(0), "Zero address detected");
    require(_AARS <= _AART, "Safe AAR must be less than or equal to target AAR");
    require(_AARC <= _AARS, "Circuit breaker AAR must be less than or equal to safe AAR");
    wandProtocol = _wandProtocol;
    assetPoolFactory = _assetPoolFactory;
    assetToken = _assetToken;
    assetTokenPriceFeed = _assetTokenPriceFeed;
    usbToken = _usbToken;
    xToken = address(new AssetX(_wandProtocol, address(this), _xTokenName, _xTokenSymbol));

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    _settingsDecimals = settings.decimals();
    C1 = settings.defaultC1();
    C2 = settings.defaultC2();

    settings.assertY(_Y);
    Y = _Y;

    settings.assertAART(_AART);
    AART = _AART;
    settings.assertAARS(_AARS);
    AARS = _AARS;
    settings.assertAARC(_AARC);
    AARC = _AARC;

    BasisR = settings.defaultBasisR();
    BasisR2 = settings.defaultBasisR2();
    RateR = settings.defaultRateR();
    CiruitBreakPeriod = settings.defaultCiruitBreakPeriod();
  }

  /* ================= VIEWS ================ */

  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() public view returns (uint256) {
    return _usbTotalSupply;
  }

  /**
   * @notice Current adequency ratio of the pool
   * @dev AAReth = (Meth * Peth / Musb-eth) * 100%
   */
  function AAR() public returns (uint256) {
    uint256 aar = _AAR();

    if (_aarBelowSafeThresholdTime == 0) {
      if (aar < AARS) {
        _aarBelowSafeThresholdTime = block.timestamp;
      }
    } else if (aar >= AARS) {
      _aarBelowSafeThresholdTime = 0;
    }

    if (_aarBelowCircuitBreakerThresholdTime == 0) {
      if (aar < AARC) {
        _aarBelowCircuitBreakerThresholdTime = block.timestamp;
      }
    } else if (aar >= AARC) {
      _aarBelowCircuitBreakerThresholdTime = 0;
    }

    return aar;
  }

  function AARDecimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function pairedUSBAmountToDedeemByXTokens(uint256 xTokenAmount) public view returns (uint256) {
    require(xTokenAmount > 0, "Amount must be greater than 0");
    require(AssetX(xToken).totalSupply() > 0, "No x tokens minted yet");

    // Δusb = Δethx * Musb-eth / Methx
    return xTokenAmount.mul(_usbTotalSupply).div(AssetX(xToken).totalSupply());
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * @notice Mint $USB tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintUSB(uint256 assetAmount) external payable override nonReentrant doInterestSettlement {
    uint256 aar = AAR();
    require(aar >= AARS, "Safe AAR reached");

    uint256 R2;
    if (aar >= AART) {
      R2 = 0;
    }
    else {
      R2 = AART.sub(aar).mul(BasisR2).div(10 ** _settingsDecimals);
    }

    // Δusb = Δeth * Peth * (1 - R2)
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    uint256 tokenAmount = assetAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(
      (10 ** _settingsDecimals).sub(R2)
    ).div(10 ** _settingsDecimals);

    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);
    USB(usbToken).mint(_msgSender(), tokenAmount);
    _usbTotalSupply = _usbTotalSupply.add(tokenAmount);

    emit USBMinted(_msgSender(), assetAmount, assetTokenPrice, assetTokenPriceDecimals, tokenAmount);
  }

  /**
   * @notice Mint X tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintXTokens(uint256 assetAmount) external payable override nonReentrant doInterestSettlement {
    uint256 aar = AAR();
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerThresholdTime) >= CiruitBreakPeriod), "Circuit breaker AAR reached");

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();

    // Initial mint: Δethx = Δeth
    uint256 xTokenAmount = assetAmount;

    // Otherwise: Δethx = (Δeth * Peth * Methx) / (Meth * Peth - Musb-eth)
    if (AssetX(xToken).totalSupply() > 0) {
      uint256 assetTotalAmount = _getAssetTotalAmount();
      uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
      xTokenAmount = assetAmount.mul(xTokenTotalAmount).mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).div(
        assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(_usbTotalSupply)
      );
    }

    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);
    AssetX(xToken).mint(_msgSender(), xTokenAmount);
    emit XTokenMinted(_msgSender(), assetAmount, assetTokenPrice, assetTokenPriceDecimals, xTokenAmount);
  }

  /**
   * @notice Redeem asset tokens with $USB
   * @param usbAmount: Amount of $USB tokens used to redeem for asset tokens
   */
  function redeemByUSB(uint256 usbAmount) external override nonReentrant doInterestSettlement {
    require(usbAmount > 0, "Amount must be greater than 0");

    uint256 assetAmount = 0;

    uint256 aar = AAR();
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();

    // if AAR >= 100%,  Δeth = (Δusb / Peth) * (1 -C1)
    uint256 fee = 0;
    if (aar >= 10 ** AARDecimals()) {
      uint256 total = usbAmount.mul(10 ** assetTokenPriceDecimals).div(assetTokenPrice);
      fee = total.mul(C1).div(10 ** _settingsDecimals);
      assetAmount = total.sub(fee);
    }
    // else if AAR < 100%, Δeth = (Δusb * Meth) / Musb-eth
    else {
      uint256 assetTotalAmount = _getAssetTotalAmount();
      assetAmount = usbAmount.mul(assetTotalAmount).div(_usbTotalSupply);
    }

    USB(usbToken).burn(_msgSender(), usbAmount);
    _usbTotalSupply = _usbTotalSupply.sub(usbAmount);

    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);
    emit AssetRedeemedWithUSB(_msgSender(), usbAmount, assetAmount, assetTokenPrice, assetTokenPriceDecimals);

    if (fee > 0) {
      address treasury = IProtocolSettings(WandProtocol(wandProtocol).settings()).treasury();
      TokensTransfer.transferTokens(assetToken, address(this), treasury, fee);
      emit AssetRedeemedWithUSBFeeCollected(_msgSender(), treasury, usbAmount, fee, assetTokenPrice, assetTokenPriceDecimals);
    }
  }

  /**
   * @notice Redeem asset tokens with X tokens
   * @param xTokenAmount: Amount of X tokens used to redeem for asset tokens
   */
  function redeemByXTokens(uint256 xTokenAmount) external override nonReentrant doInterestSettlement {
    uint256 pairedUSBAmount = pairedUSBAmountToDedeemByXTokens(xTokenAmount);

    // Δeth = Δethx * Meth / Methx * (1 -C2)
    uint256 total = xTokenAmount.mul(_getAssetTotalAmount()).div(AssetX(xToken).totalSupply());
    uint256 fee = total.mul(C2).div(10 ** _settingsDecimals);
    uint256 assetAmount = total.sub(fee);

    USB(usbToken).burn(_msgSender(), pairedUSBAmount);
    _usbTotalSupply = _usbTotalSupply.sub(pairedUSBAmount);
    AssetX(xToken).burn(_msgSender(), xTokenAmount);

    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);
    emit AssetRedeemedWithXTokens(_msgSender(), xTokenAmount, pairedUSBAmount, assetAmount);

    if (fee > 0) {
      address treasury = IProtocolSettings(WandProtocol(wandProtocol).settings()).treasury();
      TokensTransfer.transferTokens(assetToken, address(this), treasury, fee);
      emit AssetRedeemedWithXTokensFeeCollected(_msgSender(), treasury, xTokenAmount, fee, pairedUSBAmount, assetAmount);
    }
  }

  function usbToXTokens(uint256 usbAmount) external override nonReentrant doInterestSettlement {
    require(usbAmount > 0, "Amount must be greater than 0");

    // 𝑟 = 0 𝑖𝑓 𝐴𝐴𝑅 ≥ 2
    // 𝑟 = 0.1 × (𝑡𝑎𝑟𝑔𝑒𝑡𝐴𝐴𝑅 − 𝐴𝐴𝑅) 𝑖𝑓 1.5 <= 𝐴𝐴𝑅 < 2; more specifically, 0.1 is BasisR
    // 𝑟 = 0.05 + 0.001 × 𝑡(h𝑟𝑠) 𝑖𝑓 𝐴𝐴𝑅 < 1.5；more specifically, 0.05 = 0.1 x (AART - AARS), 0.001 is RateR
    uint256 aar = AAR();
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerThresholdTime) >= CiruitBreakPeriod), "Circuit breaker AAR reached");
    uint256 r;
    if (aar >= AART) {
      r = 0;
    }
    else if (aar >= AARS) {
      r = aar.sub(AARS).mul(BasisR).div(10 ** _settingsDecimals);
    }
    else {
      require(_aarBelowSafeThresholdTime > 0, "AAR dropping below safe threshold time should be recorded");
      uint256 base = AART.sub(AARS).mul(BasisR).div(10 ** _settingsDecimals);
      uint256 timeElapsed = block.timestamp.sub(_aarBelowSafeThresholdTime);
      r = base.add(RateR.mul(timeElapsed).div(1 hours));
    }

    // Δethx = (Δusb * Methx * (1 + r)) / (Meth * Peth - Musb-eth)
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    uint256 ethxAmount = usbAmount.mul(AssetX(xToken).totalSupply()).mul((10 ** AARDecimals()).add(r)).div(10 ** AARDecimals()).div(
      _getAssetTotalAmount().mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(_usbTotalSupply)
    );

    USB(usbToken).burn(_msgSender(), usbAmount);
    _usbTotalSupply = _usbTotalSupply.sub(usbAmount);
    AssetX(xToken).mint(_msgSender(), ethxAmount);

    emit UsbToXTokens(_msgSender(), usbAmount, ethxAmount, aar, r, assetTokenPrice, assetTokenPriceDecimals);
  }

  function interestSettlement() external nonReentrant doInterestSettlement {
    // Nothing to do here
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function setC1(uint256 newC1) external nonReentrant onlyAssetPoolFactory {
    require(newC1 != C1, "Same redemption fee");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertC1(newC1);
    
    C1 = newC1;
    emit UpdatedC1(C1, newC1);
  }

  function setC2(uint256 newC2) external nonReentrant onlyAssetPoolFactory {
    require(newC2 != C2, "Same redemption fee");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertC2(newC2);

    C2 = newC2;
    emit UpdatedC2(C2, newC2);
  }

  function setY(uint256 newY) external nonReentrant onlyAssetPoolFactory {
    require(newY != Y, "Same yield rate");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertY(newY);

    Y = newY;
    emit UpdatedY(Y, newY);
  }

  function setBasisR(uint256 newBasisR) external nonReentrant onlyAssetPoolFactory {
    require(newBasisR != BasisR, "Same basis of r");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertBasisR(newBasisR);

    BasisR = newBasisR;
    emit UpdatedBasisR(BasisR, newBasisR);
  }

  function setRateR(uint256 newRateR) external nonReentrant onlyAssetPoolFactory {
    require(newRateR != RateR, "Same rate of r");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertRateR(newRateR);

    RateR = newRateR;
    emit UpdatedRateR(RateR, newRateR);
  }

  function setBasisR2(uint256 newBasisR2) external nonReentrant onlyAssetPoolFactory {
    require(newBasisR2 != BasisR2, "Same basis of R2");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertBasisR2(newBasisR2);

    BasisR2 = newBasisR2;
    emit UpdatedBasisR2(BasisR2, newBasisR2);
  }

  function setCiruitBreakPeriod(uint256 newCiruitBreakPeriod) external nonReentrant onlyAssetPoolFactory {
    require(newCiruitBreakPeriod != CiruitBreakPeriod, "Same circuit breaker period");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertCiruitBreakPeriod(newCiruitBreakPeriod);

    CiruitBreakPeriod = newCiruitBreakPeriod;
    emit UpdateCiruitBreakPeriod(CiruitBreakPeriod, newCiruitBreakPeriod);
  }

  function setAART(uint256 newAART) external nonReentrant onlyAssetPoolFactory {
    require(newAART != AART, "Same target AAR");
    require(newAART >= AARS, "Target AAR must be greater than or equal to safe AAR");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertAART(newAART);

    AART = newAART;
    emit UpdatedAART(AART, newAART);
  }

  function setAARS(uint256 newAARS) external nonReentrant onlyAssetPoolFactory {
    require(newAARS != AARS, "Same safe AAR");
    require(newAARS <= AART, "Safe AAR must be less than or equal to target AAR");
    require(newAARS >= AARC, "Safe AAR must be greater than or equal to circuit breaker AAR");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertAARS(newAARS);

    AARS = newAARS;
    emit UpdatedAARS(AARS, newAARS);
  }

  function setAARC(uint256 newAARC) external nonReentrant onlyAssetPoolFactory {
    require(newAARC != AARC, "Same circuit breaker AAR");
    require(newAARC <= AARS, "Circuit breaker AAR must be less than or equal to safe AAR");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertAARC(newAARC);

    AARC = newAARC;
    emit UpdatedAARC(AARC, newAARC);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _getAssetTotalAmount() internal view returns (uint256) {
    if (assetToken == Constants.NATIVE_TOKEN) {
      return address(this).balance;
    }
    else {
      return IERC20(assetToken).balanceOf(address(this));
    }
  }

  function _getAssetTokenPrice() internal view returns (uint256, uint256) {
    uint256 price = IPriceFeed(assetTokenPriceFeed).latestPrice();
    uint256 priceDecimals = IPriceFeed(assetTokenPriceFeed).decimals();

    return (price, priceDecimals);
  }

  function _AAR() internal view returns (uint256) {
    uint256 assetTotalAmount = _getAssetTotalAmount();
    if (assetTotalAmount == 0) {
      return 0;
    }

    uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
    if (xTokenTotalAmount == 0) {
      return type(uint256).max;
    }

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** Constants.PROTOCOL_DECIMALS).div(xTokenTotalAmount);
  }

  function _interestSettlement() internal {
    if (_lastInterestSettlementTime == 0) {
      return;
    }

    // ∆ethx = (t / 365 days) * AAR * Methx
    uint256 timeElapsed = block.timestamp.sub(_lastInterestSettlementTime);
    uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
    uint256 interestAmount = timeElapsed.mul(AAR()).mul(xTokenTotalAmount).div(365 days).div(10 ** AARDecimals());

    if (interestAmount > 0) {
      IInterestPoolFactory(WandProtocol(wandProtocol).interestPoolFactory()).distributeInterestRewards(xToken, interestAmount);
      emit InterestSettlement(interestAmount);
    }
  }

  /**
   * @notice Interest generation starts when both $USB and X tokens are minted
   */
  function _startOrPauseInterestGeneration() internal {
    if (_usbTotalSupply > 0 && AssetX(xToken).totalSupply() > 0) {
      _lastInterestSettlementTime = block.timestamp;
    }
    else {
      _lastInterestSettlementTime = 0;
    }
  }

  /* ============== MODIFIERS =============== */

  modifier onlyAssetPoolFactory() {
    require(_msgSender() == assetPoolFactory, "Caller is not AssetPoolFactory");
    _;
  }

  modifier doInterestSettlement() {
    _interestSettlement();
    _;
    _startOrPauseInterestGeneration();
  }

  /* =============== EVENTS ============= */

  event UpdatedC1(uint256 prevC1, uint256 newC1);
  event UpdatedC2(uint256 prevC2, uint256 newC2);
  event UpdatedY(uint256 prevY, uint256 newY);
  event UpdatedAART(uint256 prevAART, uint256 newAART);
  event UpdatedAARS(uint256 prevAARS, uint256 newAARS);
  event UpdatedAARC(uint256 prevAARC, uint256 newAARC);
  event UpdatedBasisR(uint256 prevBasisR, uint256 newBasisR);
  event UpdatedRateR(uint256 prevRateR, uint256 newRateR);
  event UpdatedBasisR2(uint256 prevBasisR2, uint256 newBasisR2);
  event UpdateCiruitBreakPeriod(uint256 prevCiruitBreakPeriod, uint256 newCiruitBreakPeriod);

  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 usbTokenAmount);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 xTokenAmount);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSBFeeCollected(address indexed user, address indexed feeTo, uint256 usbTokenAmount, uint256 feeAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokens(address indexed user, uint256 xTokenAmount, uint256 pairedUSBAmount, uint256 assetAmount);
  event AssetRedeemedWithXTokensFeeCollected(address indexed user, address indexed feeTo, uint256 xTokenAmount, uint256 fee, uint256 pairedUSBAmount, uint256 assetAmount);
  event UsbToXTokens(address indexed user, uint256 usbAmount, uint256 xTokenAmount, uint256 aar, uint256 r, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);

  event InterestSettlement(uint256 interestAmount);
}