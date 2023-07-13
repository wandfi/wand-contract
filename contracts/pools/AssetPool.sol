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
  uint256 internal _undistributedInterest;

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

  function calculateXTokensOut(address account, uint256 usbAmount) public returns (uint256) {
    require(usbAmount > 0, "Amount must be greater than 0");
    require(usbAmount <= USB(usbToken).balanceOf(account), "Not enough $USB balance");

    uint256 aar = AAR();
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerThresholdTime) >= CiruitBreakPeriod), "Circuit breaker AAR reached");
    
    uint256 assetTotalAmount = _getAssetTotalAmount();
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    uint256 usbSwapableAmountBelowAARS = 0;
    uint256 usbSwapableAmountAboveAARS = 0;
    uint256 usbSwapableAmountAboveAART = 0;
    uint256 xTokenOutBelowAARS = 0;
    uint256 xTokenOutAboveAARS = 0;
    uint256 xTokenOutAboveAART = 0;

    // 𝑟 = 0 𝑖𝑓 𝐴𝐴𝑅 ≥ 2
    // 𝑟 = BasisR × (𝐴𝐴𝑅𝑇 − 𝐴𝐴𝑅) 𝑖𝑓 1.5 <= 𝐴𝐴𝑅 < 2;
    // 𝑟 = BasisR × (𝐴𝐴𝑅𝑇 − 𝐴𝐴𝑅) + RateR × 𝑡(h𝑟𝑠) 𝑖𝑓 𝐴𝐴𝑅 < 1.5;

    // Δethx = Δusb * Methx * (1 + r) / (Meth * Peth - Musb-eth)

    // AAReth = (Meth * Peth / Musb-eth) * 100%

    uint256 remainingUSBAmount = usbAmount;
    uint256 aarForRemainingUSB = aar;
    uint256 usbTotalSupplyForRemainingUSB = _usbTotalSupply;
    uint256 xTokenTotalSupplyForRemainingUSB = AssetX(xToken).totalSupply();
    if (aarForRemainingUSB < AARS) {
      require(_aarBelowSafeThresholdTime > 0, "AAR dropping below safe threshold time should be recorded");
      uint256 base = AART.sub(aarForRemainingUSB).mul(BasisR).div(10 ** _settingsDecimals);
      uint256 timeElapsed = block.timestamp.sub(_aarBelowSafeThresholdTime);
      uint256 r = base.add(RateR.mul(timeElapsed).div(1 hours));

      // Well, how many $USB need be burned to make AAR = AARS?
      uint256 targetUSBAmount = assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** Constants.PROTOCOL_DECIMALS).div(AARS);
      uint256 maxSwapableUSBAmount = usbTotalSupplyForRemainingUSB.sub(targetUSBAmount);
      if (remainingUSBAmount <= maxSwapableUSBAmount) {
        usbSwapableAmountBelowAARS = remainingUSBAmount;
        remainingUSBAmount = 0;
      } else {
        usbSwapableAmountBelowAARS = maxSwapableUSBAmount;
        remainingUSBAmount = remainingUSBAmount.sub(usbSwapableAmountBelowAARS);
      }
      aarForRemainingUSB = AARS;
      xTokenOutBelowAARS = usbSwapableAmountBelowAARS.mul(xTokenTotalSupplyForRemainingUSB).mul((10 ** AARDecimals()).add(r)).div(10 ** AARDecimals()).div(
        assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(usbTotalSupplyForRemainingUSB)
      );
      xTokenTotalSupplyForRemainingUSB = xTokenTotalSupplyForRemainingUSB.add(xTokenOutBelowAARS);
      usbTotalSupplyForRemainingUSB = usbTotalSupplyForRemainingUSB.sub(usbSwapableAmountBelowAARS);
    }

    if (remainingUSBAmount > 0 && aarForRemainingUSB < AART) {
      uint256 r = AART.sub(aarForRemainingUSB).mul(BasisR).div(10 ** _settingsDecimals);

      // Well, how many $USB need be burned to make AAR = AART?
      uint256 targetUSBAmount = assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** Constants.PROTOCOL_DECIMALS).div(AART);
      uint256 maxSwapableUSBAmount = usbTotalSupplyForRemainingUSB.sub(targetUSBAmount);
      if (remainingUSBAmount <= maxSwapableUSBAmount) {
        usbSwapableAmountAboveAARS = remainingUSBAmount;
        remainingUSBAmount = 0;
      } else {
        usbSwapableAmountAboveAARS = maxSwapableUSBAmount;
        remainingUSBAmount = remainingUSBAmount.sub(usbSwapableAmountAboveAARS);
      }
      aarForRemainingUSB = AART;
      xTokenOutAboveAARS = usbSwapableAmountAboveAARS.mul(xTokenTotalSupplyForRemainingUSB).mul((10 ** AARDecimals()).add(r)).div(10 ** AARDecimals()).div(
        assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(usbTotalSupplyForRemainingUSB)
      );
      xTokenTotalSupplyForRemainingUSB = xTokenTotalSupplyForRemainingUSB.add(xTokenOutAboveAARS);
      usbTotalSupplyForRemainingUSB = usbTotalSupplyForRemainingUSB.sub(usbSwapableAmountAboveAARS);
    }

    if (remainingUSBAmount > 0 && aarForRemainingUSB >= AART) {
      uint256 r = 0;

      usbSwapableAmountAboveAART = remainingUSBAmount;
      xTokenOutAboveAART = usbSwapableAmountAboveAART.mul(xTokenTotalSupplyForRemainingUSB).mul((10 ** AARDecimals()).add(r)).div(10 ** AARDecimals()).div(
        assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(usbTotalSupplyForRemainingUSB)
      );
    }

    return xTokenOutBelowAARS.add(xTokenOutAboveAARS).add(xTokenOutAboveAART);
  }

  function calculateUSBMintOut(uint256 assetAmount) public returns (uint256) {
    require(assetAmount > 0, "Amount must be greater than 0");
    uint256 aar = AAR();
    require(aar >= AARS, "Safe AAR reached");

    // Δusb = Δeth * Peth * (1 - R2)
    // AAReth = (Meth * Peth / Musb-eth) * 100%

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    uint256 remainingAssetAmount = assetAmount;
    uint256 assetDepositableAmountBelowAART = 0;
    uint256 assetDepositableAmountAboveAART = 0;
    uint256 usbMintOutBelowAART = 0;
    uint256 usbMintOutAboveAART = 0;
    uint256 aarForRemainingAsset = aar;

    if (aarForRemainingAsset < AART) {
      uint256 R2 = AART.sub(aar).mul(BasisR2).div(10 ** _settingsDecimals);

      /**
       * Well, how many $USB need be minted to make AAR = AART?
       * 
       * Δusb = Δeth * Peth * (1 - R2)
       * AAReth = (Meth * Peth / Musb-eth) * 100%
       * 
       * ==> 
       * 
       * AAReth * Musb-eth = Meth * Peth *
       * AART * (Musb-eth + Δusb) = (Meth + Δeth) * Peth
       * AART * (Musb-eth + Δeth * Peth * (1 - R2)) = (Meth + Δeth) * Peth
       * AART * Musb-eth + AART * Δeth * Peth * (1 - R2) = Meth * Peth + Δeth * Peth
       * Δeth * Peth - AART * Δeth * Peth * (1 - R2) = AART * Musb-eth - Meth * Peth
       * Δeth * Peth * (1 - AART + AART * R2) = AART * Musb-eth - Meth * Peth
       * 
       * ==>
       * 
       * Δeth = (AART * Musb-eth - Meth * Peth) / (Peth * (1 - AART + AART * R2))
       * -Δeth = (AART * Musb-eth - Meth * Peth) / Peth / (AART - AART * R2 - 1))
       * Δusb = Δeth * Peth * (1 - R2)
       */
      uint256 assetTotalAmount = _getAssetTotalAmount();
      uint256 maxDepositableAssetAmount = AART.mul(_usbTotalSupply).div(10 ** _settingsDecimals).sub(assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals))
        .mul(10 ** assetTokenPriceDecimals).div(assetTokenPrice)
        .mul(10 ** _settingsDecimals).div(AART.sub(AART.mul(R2).div(10 ** _settingsDecimals)).sub(10 ** _settingsDecimals));
      if (remainingAssetAmount <= maxDepositableAssetAmount) {
        assetDepositableAmountBelowAART = remainingAssetAmount;
        remainingAssetAmount = 0;
      }
      else {
        assetDepositableAmountBelowAART = maxDepositableAssetAmount;
        remainingAssetAmount = remainingAssetAmount.sub(assetDepositableAmountBelowAART);
      }
      usbMintOutBelowAART = assetDepositableAmountBelowAART.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul((10 ** _settingsDecimals).sub(R2)).div(10 ** _settingsDecimals);
      aarForRemainingAsset = AART;
    }

    if (remainingAssetAmount > 0 && aarForRemainingAsset >= AART) {
      uint256 R2 = 0;
      assetDepositableAmountAboveAART = remainingAssetAmount;
      usbMintOutAboveAART = assetDepositableAmountAboveAART.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul((10 ** _settingsDecimals).sub(R2)).div(10 ** _settingsDecimals);
    }

    return usbMintOutBelowAART.add(usbMintOutAboveAART);
  }


  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * @notice Mint $USB tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintUSB(uint256 assetAmount) external payable override nonReentrant doInterestSettlement {
    uint256 usbOutAmount = calculateUSBMintOut(assetAmount);

    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);
    USB(usbToken).mint(_msgSender(), usbOutAmount);
    _usbTotalSupply = _usbTotalSupply.add(usbOutAmount);

    emit USBMinted(_msgSender(), assetAmount, usbOutAmount);
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
      // C1 only takes effect when AAR >= [2 * (AART - 100%) + 100%]
      if (aar >= AART.sub(10 ** AARDecimals()).mul(2).add(10 ** AARDecimals())) {
        fee = total.mul(C1).div(10 ** _settingsDecimals);
      }
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
    uint256 xTokenOut = calculateXTokensOut(_msgSender(), usbAmount);

    USB(usbToken).burn(_msgSender(), usbAmount);
    _usbTotalSupply = _usbTotalSupply.sub(usbAmount);
    AssetX(xToken).mint(_msgSender(), xTokenOut);

    emit UsbToXTokens(_msgSender(), usbAmount, xTokenOut);
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

  /**
   * AAReth = (Meth * Peth / Musb-eth) * 100%
   */
  function _AAR() internal view returns (uint256) {
    uint256 assetTotalAmount = _getAssetTotalAmount();
    if (assetTotalAmount == 0) {
      return 0;
    }

    if (_usbTotalSupply == 0) {
      return type(uint256).max;
    }

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** Constants.PROTOCOL_DECIMALS).div(_usbTotalSupply);
  }

  function _interestSettlement() internal {
    if (_lastInterestSettlementTime == 0) {
      return;
    }

    // ∆ethx = (t / 365 days) * AAR * Methx
    uint256 timeElapsed = block.timestamp.sub(_lastInterestSettlementTime);
    uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
    uint256 newInterestAmount = timeElapsed.mul(AAR()).mul(xTokenTotalAmount).div(365 days).div(10 ** AARDecimals());
    if (newInterestAmount > 0) {
      AssetX(xToken).mint(address(this), newInterestAmount);
    }
    uint256 totalInterestAmount = newInterestAmount.add(_undistributedInterest);

    if (totalInterestAmount > 0) {
      IInterestPoolFactory interestPoolFactory = IInterestPoolFactory(WandProtocol(wandProtocol).interestPoolFactory());
      AssetX(xToken).approve(address(interestPoolFactory), totalInterestAmount);
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

  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 usbTokenAmount);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 xTokenAmount);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSBFeeCollected(address indexed user, address indexed feeTo, uint256 usbTokenAmount, uint256 feeAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokens(address indexed user, uint256 xTokenAmount, uint256 pairedUSBAmount, uint256 assetAmount);
  event AssetRedeemedWithXTokensFeeCollected(address indexed user, address indexed feeTo, uint256 xTokenAmount, uint256 fee, uint256 pairedUSBAmount, uint256 assetAmount);
  event UsbToXTokens(address indexed user, uint256 usbAmount, uint256 xTokenAmount);

  event InterestSettlement(uint256 interestAmount, bool distributed);
}