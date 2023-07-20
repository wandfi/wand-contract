// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "hardhat/console.sol";

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

  uint256 internal _aarBelowSafeLineTime;
  uint256 internal _aarBelowCircuitBreakerLineTime;

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

  function getAssetTotalAmount() public view returns (uint256) {
    return _getAssetTotalAmount();
  }

  /**
   * @notice Current adequency ratio of the pool
   * @dev AAReth = (M_ETH * P_ETH / Musb-eth) * 100%
   */
  function AAR() public view returns (uint256) {
    if (_usbTotalSupply == 0) {
      return type(uint256).max;
    }

    uint256 assetTotalAmount = _getAssetTotalAmount();
    if (assetTotalAmount == 0) {
      return 0;
    }

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** AARDecimals()).div(_usbTotalSupply);
  }

  function AARDecimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function pairedUSBAmountToRedeemByXTokens(uint256 xTokenAmount) public view returns (uint256) {
    require(xTokenAmount > 0, "Amount must be greater than 0");
    require(AssetX(xToken).totalSupply() > 0, "No x tokens minted yet");

    // Δusb = Δethx * Musb-eth / M_ETHx
    return xTokenAmount.mul(_usbTotalSupply).div(AssetX(xToken).totalSupply());
  }

 /**
  * This is to workaround the following complier error:
  *  CompilerError: Stack too deep, try removing local variables.
  */
  struct CalculateXTokensOutVars {
    uint256 aar;
    uint256 Delat_USB; // Δusb
    uint256 M_USB_ETH;
    uint256 M_ETHx;
    uint256 M_ETH;
    uint256 P_ETH;
    uint256 P_ETH_Decimals;
    uint256 aar_;
    uint256 r;
  }

  struct Terms {
    uint256 T1;
    uint256 T2;
    uint256 T3;
    uint256 T4;
    uint256 T5;
    uint256 T6;
    uint256 T7;
    uint256 T8;
  }

  function calculateUSBToXTokensOut(address account, uint256 usbAmount) public view returns (uint256) {
    require(usbAmount > 0, "Amount must be greater than 0");
    require(usbAmount <= USB(usbToken).balanceOf(account), "Not enough $USB balance");
    require(usbAmount < _usbTotalSupply, "Too much $USB amount");

    CalculateXTokensOutVars memory vars;
    vars.aar = AAR();
    require(vars.aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= CiruitBreakPeriod), "Circuit breaker AAR reached");
    
    vars.Delat_USB = usbAmount;
    vars.M_USB_ETH = _usbTotalSupply;
    vars.M_ETHx = AssetX(xToken).totalSupply();
    vars.M_ETH = _getAssetTotalAmount();
    (vars.P_ETH, vars.P_ETH_Decimals) = _getAssetTokenPrice();

    // AAR'eth = (M_ETH * P_ETH / (Musb-eth - Δusb)) * 100%
    vars.aar_ = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(vars.M_USB_ETH.sub(vars.Delat_USB));

    // 𝑟 = 0 𝑖𝑓 𝐴𝐴𝑅 ≥ 2
    // 𝑟 = BasisR × (𝐴𝐴𝑅𝑇 − 𝐴𝐴𝑅) 𝑖𝑓 1.5 <= 𝐴𝐴𝑅 < 2;
    // 𝑟 = BasisR × (𝐴𝐴𝑅𝑇 − 𝐴𝐴𝑅S) + RateR × 𝑡(h𝑟𝑠) 𝑖𝑓 𝐴𝐴𝑅 < 1.5;
    vars.r = 0;
    if (vars.aar < AARS) {
      assert(_aarBelowSafeLineTime > 0);
      uint256 base = AART.sub(AARS).mul(BasisR).div(10 ** _settingsDecimals);
      uint256 timeElapsed = block.timestamp.sub(_aarBelowSafeLineTime);
      vars.r = base.add(RateR.mul(timeElapsed).div(1 hours));
    } else if (vars.aar < AART) {
      vars.r = AART.sub(vars.aar).mul(BasisR).div(10 ** _settingsDecimals);
    }

    // If AAR'eth <= AAARS or AAReth >= AART
    //  Δethx = Δusb * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth)
    if (vars.aar_ <= AARS || vars.aar >= AART) {
      return vars.Delat_USB.mul(vars.M_ETHx).mul((10 ** AARDecimals()).add(vars.r)).div(10 ** AARDecimals()).div(
        vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH)
      );
    }

    // If AARS <= AAR'eth <= AART, and AAReth <= AARS
    //  Δethx = (Musb-eth - M_ETH * P_ETH / AARS) * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + r) 
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / AARS) * M_ETHx / (M_ETHx * P_ETH - Musb-eth)
    //    * (1 + (2 * AART - AARS - AAR'eth) * 0.1 / 2)
    if (vars.aar_ >= AARS && vars.aar_ <= AART && vars.aar <= AARS) {
      Terms memory T;
      T.T1 = vars.M_USB_ETH.sub(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AARS)); // (Musb-eth - M_ETH * P_ETH / AARS)
      T.T2 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T3 = (10 ** AARDecimals()).add(vars.r).div(10 ** AARDecimals());  // (1 + r)
      T.T4 = vars.Delat_USB.sub(vars.M_USB_ETH).add(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AARS)); // (Δusb - Musb-eth + M_ETH * P_ETH / AARS)
      T.T5 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETHx * P_ETH - Musb-eth)
      T.T6 = (10 ** AARDecimals()).add(
        uint256(2).mul(AART).sub(AARS).sub(vars.aar_).mul(BasisR).div(2).div(10 ** _settingsDecimals)
      ).div(10 ** AARDecimals()); // (1 + (2 * AART - AARS - AAR'eth) * 0.1 / 2)

      return T.T1.mul(vars.M_ETHx).div(T.T2).mul(T.T3).add(T.T4.mul(vars.M_ETHx).div(T.T5).mul(T.T6));
    }

    // If AARS <= AAReth <= AART, and AARS <= AAR'eth <= AART
    //  Δethx = Δusb * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (AAR'eth - AAReth) * 0.1 / 2)
    if (vars.aar >= AARS && vars.aar <= AART && vars.aar_ >= AARS && vars.aar_ <= AART) {
      return vars.Delat_USB.mul(vars.M_ETHx).div(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH)) // Δusb * M_ETHx / (M_ETH * P_ETH - Musb-eth)
        .mul(10 ** AARDecimals().add(  // * (1 + (AAR'eth - AAReth) * 0.1 / 2)
          (vars.aar_).sub(vars.aar)).mul(BasisR).div(2).div(10 ** _settingsDecimals)
        ).div(10 ** AARDecimals());
    }

    // If AAR'eth >= AART, and AAReth <= AARS
    //  Δethx = (Musb-eth - M_ETH * P_ETH / AARS) * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + r)
    //    + (M_ETH * P_ETH / AARS - M_ETH * P_ETH / AART)
    //    * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (AART - AARS) * 0.1 / 2)
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / AART) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    if (vars.aar_ >= AART && vars.aar <= AARS) {
      Terms memory T;
      T.T1 = vars.M_USB_ETH.sub(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AARS)); // (Musb-eth - M_ETH * P_ETH / AARS)
      T.T2 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T3 = (10 ** AARDecimals()).add(vars.r).div(10 ** AARDecimals());  // (1 + r)
      T.T4 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AARS)
        .sub(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AART)); // (M_ETH * P_ETH / AARS - M_ETH * P_ETH / AART)
      T.T5 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETHx * P_ETH - Musb-eth)
      T.T6 = (10 ** AARDecimals()).add(AART.sub(AARS).mul(BasisR).div(2).div(10 ** _settingsDecimals)).div(10 ** AARDecimals()); // (1 + (AART - AARS) * 0.1 / 2)
      T.T7 = vars.Delat_USB.sub(vars.M_USB_ETH).add(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AART)); // (Δusb - Musb-eth + M_ETH * P_ETH / AART)
      T.T8 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)

      return T.T1.mul(vars.M_ETHx).div(T.T2).mul(T.T3).add(T.T4.mul(vars.M_ETHx).div(T.T5).mul(T.T6)).add(T.T7.mul(vars.M_ETHx).div(T.T8));
    }

    // If AAR'eth >= AART, and AARS <= AAReth <= AART
    //  Δethx = (Musb-eth - M_ETH * P_ETH / AART) 
    //      * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    //      * (1 + (AART - AAReth) * 0.1 / 2)
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / AART) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    if (vars.aar_ >= AART && vars.aar >= AARS && vars.aar <= AART) {
      Terms memory T;
      T.T1 = vars.M_USB_ETH.sub(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AART)); // (Musb-eth - M_ETH * P_ETH / AART)
      T.T2 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T3 = (10 ** AARDecimals()).add(AART.sub(vars.aar).mul(BasisR).div(2).div(10 ** _settingsDecimals)).div(10 ** AARDecimals()); // (1 + (AART - AAReth) * 0.1 / 2)
      T.T4 = vars.Delat_USB.sub(vars.M_USB_ETH).add(vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(AART)); // (Δusb - Musb-eth + M_ETH * P_ETH / AART)
      T.T5 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(vars.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)

      return T.T1.mul(vars.M_ETHx).div(T.T2).mul(T.T3).add(T.T4.mul(vars.M_ETHx).div(T.T5));
    }

    revert("Should not reach here");
  }

  /**
   * This is to workaround the following complier error:
   *  CompilerError: Stack too deep, try removing local variables.
   */
  struct CalculateUSBMintOutLocalVars {
    uint256 aar;
    uint256 Deth; // Δeth
    uint256 M_USB_ETH;
    uint256 M_ETHx;
    uint256 M_ETH;
    uint256 P_ETH;
    uint256 P_ETH_Decimals;
    uint256 aar_;
  }

  function calculateMintUSBOut(uint256 assetAmount) public view returns (uint256) {
    require(assetAmount > 0, "Amount must be greater than 0");

    CalculateUSBMintOutLocalVars memory vars;
    vars.aar = AAR();
    require(vars.aar >= AARS, "AAR Below Safe Threshold");
    
    vars.Deth = assetAmount;
    vars.M_USB_ETH = _usbTotalSupply;
    vars.M_ETHx = AssetX(xToken).totalSupply();
    vars.M_ETH = _getAssetTotalAmount();
    (vars.P_ETH, vars.P_ETH_Decimals) = _getAssetTokenPrice();

    // AAR'eth = (Δeth + M_ETH)* P_ETH / (Musb-eth + Δeth * P_ETH)) * 100%
    vars.aar_ = vars.Deth.add(vars.M_ETH).mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(10 ** AARDecimals()).div(
      vars.M_USB_ETH.add(vars.Deth.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals))
    );
    // console.log('calculateMintUSBOut, aar: %s, aar`: %s', vars.aar, vars.aar_);

    // If AAR'eth <= AARS, or AAReth >= AART
    //  Δusb = Δeth * P_ETH
    if (vars.aar_ <= AARS || vars.aar >= AART) {
      return vars.Deth.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals);
    }

    // If AARS <= AAR'eth <= AART, and AAReth >= AART
    //  Δusb = (M_ETH * P_ETH - AART * Musb-eth) / (AART - 1)
    //    + (Δeth * P_ETH - (M_ETH * P_ETH - AART * Musb-eth) / (AART - 1))
    //      * (1 - (AART - AAR'eth) * 0.06 / 2)
    if (vars.aar_ >= AARS && vars.aar_ <= AART && vars.aar >= AART) {
      Terms memory T;
      T.T1 = vars.M_ETH.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(AART.mul(vars.M_USB_ETH).div(10 ** AARDecimals())); // (M_ETH * P_ETH - AART * Musb-eth)
      T.T2 = AART.sub(10 ** AARDecimals()); // (AART - 1)
      T.T3 = vars.Deth.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).sub(T.T1.div(T.T2)); // (Δeth * P_ETH - (M_ETH * P_ETH - AART * Musb-eth) / (AART - 1))
      T.T4 = (10 ** _settingsDecimals).sub(
        AART.sub(vars.aar_).mul(BasisR2).div(2).div(10 ** _settingsDecimals)
      ); // (1 - (AART - AAR'eth) * 0.06 / 2)

      return T.T1.div(T.T2).add(T.T3.mul(T.T4));
    }

    // If AARS <= AAR'eth <= AART, and AARS <= AAReth <= AART
    //  Δusb = Δeth * P_ETH * (1 - (AAReth - AAR'eth) * 0.06 / 2)
    if (vars.aar_ >= AARS && vars.aar_ <= AART && vars.aar >= AARS && vars.aar <= AART) {
      return vars.Deth.mul(vars.P_ETH).div(10 ** vars.P_ETH_Decimals).mul(
        (10 ** AARDecimals()).sub(
          vars.aar.sub(vars.aar_).mul(BasisR2).div(2).div(10 ** _settingsDecimals)
        )
      ).div(10 ** AARDecimals());
    }

    revert("Should not reach here");
  }

  function calculateMintXTokensOut(uint256 assetAmount) public view returns (uint256) {
    uint256 aar = AAR();
    require(aar > 10 ** AARDecimals(), "AAR Below 100%");
    // console.log('calculateMintXTokensOut, _aarBelowCircuitBreakerLineTime: %s, now: %s', _aarBelowCircuitBreakerLineTime, block.timestamp);
    require(aar >= AARC || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= CiruitBreakPeriod), "AAR Below Circuit Breaker AAR Threshold");

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();

    // Initial mint: Δethx = Δeth
    uint256 xTokenAmount = assetAmount;

    // Otherwise: Δethx = (Δeth * P_ETH * M_ETHx) / (M_ETH * P_ETH - Musb-eth)
    if (AssetX(xToken).totalSupply() > 0) {
      uint256 assetTotalAmount = _getAssetTotalAmount();
      uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
      xTokenAmount = assetAmount.mul(xTokenTotalAmount).mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).div(
        assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(_usbTotalSupply)
      );
    }

    return xTokenAmount;
  }

  function calculateInterest() public view returns (uint256, uint256) {
    uint256 newInterestAmount = 0;
    uint256 totalInterestAmount = newInterestAmount.add(_undistributedInterest);

    if (_lastInterestSettlementTime == 0) {
      return (newInterestAmount, totalInterestAmount);
    }

    // ∆ethx = (t / 365 days) * Y * M_ETHx
    uint256 timeElapsed = block.timestamp.sub(_lastInterestSettlementTime);
    uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
    newInterestAmount = timeElapsed.mul(Y).mul(xTokenTotalAmount).div(365 days).div(10 ** _settingsDecimals);
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
    USB(usbToken).mint(_msgSender(), usbOutAmount);
    _usbTotalSupply = _usbTotalSupply.add(usbOutAmount);

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
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
    AssetX(xToken).mint(_msgSender(), xTokenAmount);
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
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
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();

    // if AAR >= 100%,  Δeth = (Δusb / P_ETH) * (1 -C1)
    uint256 fee = 0;
    if (aar >= 10 ** AARDecimals()) {
      uint256 total = usbAmount.mul(10 ** assetTokenPriceDecimals).div(assetTokenPrice);
      // C1 only takes effect when AAR >= [2 * (AART - 100%) + 100%]
      if (aar >= AART.sub(10 ** AARDecimals()).mul(2).add(10 ** AARDecimals())) {
        fee = total.mul(C1).div(10 ** _settingsDecimals);
      }
      assetAmount = total.sub(fee);
    }
    // else if AAR < 100%, Δeth = (Δusb * M_ETH) / Musb-eth
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
  function redeemByXTokens(uint256 xTokenAmount) external override nonReentrant doCheckAAR doSettleInterest {
    uint256 pairedUSBAmount = pairedUSBAmountToRedeemByXTokens(xTokenAmount);

    // Δeth = Δethx * M_ETH / M_ETHx * (1 -C2)
    uint256 total = xTokenAmount.mul(_getAssetTotalAmount()).div(AssetX(xToken).totalSupply());
    uint256 fee = total.mul(C2).div(10 ** _settingsDecimals);
    uint256 assetAmount = total.sub(fee);

    USB(usbToken).burn(_msgSender(), pairedUSBAmount);
    _usbTotalSupply = _usbTotalSupply.sub(pairedUSBAmount);
    AssetX(xToken).burn(_msgSender(), xTokenAmount);

    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    emit AssetRedeemedWithXTokens(_msgSender(), xTokenAmount, pairedUSBAmount, assetAmount, assetTokenPrice, assetTokenPriceDecimals);

    if (fee > 0) {
      address treasury = IProtocolSettings(WandProtocol(wandProtocol).settings()).treasury();
      TokensTransfer.transferTokens(assetToken, address(this), treasury, fee);
      emit AssetRedeemedWithXTokensFeeCollected(_msgSender(), treasury, xTokenAmount, fee, pairedUSBAmount, assetAmount, assetTokenPrice, assetTokenPriceDecimals);
    }
  }

  function usbToXTokens(uint256 usbAmount) external override nonReentrant doCheckAAR doSettleInterest {  
    uint256 xTokenOut = calculateUSBToXTokensOut(_msgSender(), usbAmount);

    USB(usbToken).burn(_msgSender(), usbAmount);
    _usbTotalSupply = _usbTotalSupply.sub(usbAmount);
    AssetX(xToken).mint(_msgSender(), xTokenOut);

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    emit UsbToXTokens(_msgSender(), usbAmount, xTokenOut, assetTokenPrice, assetTokenPriceDecimals);
  }

  function checkAAR() external override nonReentrant doCheckAAR {
    _AAR();
  }

  function settleInterest() external override nonReentrant doCheckAAR doSettleInterest {
    // Nothing to do here
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function setC1(uint256 newC1) external nonReentrant onlyAssetPoolFactory {
    require(newC1 != C1, "Same redemption fee");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertC1(newC1);
    
    uint256 prevC1 = C1;
    C1 = newC1;
    emit UpdatedC1(prevC1, C1);
  }

  function setC2(uint256 newC2) external nonReentrant onlyAssetPoolFactory {
    require(newC2 != C2, "Same redemption fee");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertC2(newC2);

    uint256 prevC2 = C2;
    C2 = newC2;
    emit UpdatedC2(prevC2, C2);
  }

  function setY(uint256 newY) external nonReentrant onlyAssetPoolFactory {
    require(newY != Y, "Same yield rate");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertY(newY);

    uint256 prevY = Y;
    Y = newY;
    emit UpdatedY(prevY, Y);
  }

  function setBasisR(uint256 newBasisR) external nonReentrant onlyAssetPoolFactory {
    require(newBasisR != BasisR, "Same basis of r");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertBasisR(newBasisR);

    uint256 prevBasisR = BasisR;
    BasisR = newBasisR;
    emit UpdatedBasisR(prevBasisR, BasisR);
  }

  function setRateR(uint256 newRateR) external nonReentrant onlyAssetPoolFactory {
    require(newRateR != RateR, "Same rate of r");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertRateR(newRateR);

    uint256 prevRateR = RateR;
    RateR = newRateR;
    emit UpdatedRateR(prevRateR, RateR);
  }

  function setBasisR2(uint256 newBasisR2) external nonReentrant onlyAssetPoolFactory {
    require(newBasisR2 != BasisR2, "Same basis of R2");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertBasisR2(newBasisR2);

    uint256 prevBasisR2 = BasisR2;
    BasisR2 = newBasisR2;
    emit UpdatedBasisR2(prevBasisR2, BasisR2);
  }

  function setCiruitBreakPeriod(uint256 newCiruitBreakPeriod) external nonReentrant onlyAssetPoolFactory {
    require(newCiruitBreakPeriod != CiruitBreakPeriod, "Same circuit breaker period");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertCiruitBreakPeriod(newCiruitBreakPeriod);

    uint256 prevCiruitBreakPeriod = CiruitBreakPeriod;
    CiruitBreakPeriod = newCiruitBreakPeriod;
    emit UpdateCiruitBreakPeriod(prevCiruitBreakPeriod, CiruitBreakPeriod);
  }

  function setAART(uint256 newAART) external nonReentrant onlyAssetPoolFactory {
    require(newAART != AART, "Same target AAR");
    require(newAART >= AARS, "Target AAR must be greater than or equal to safe AAR");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertAART(newAART);

    uint256 prevAART = AART;
    AART = newAART;
    emit UpdatedAART(prevAART, AART);
  }

  function setAARS(uint256 newAARS) external nonReentrant onlyAssetPoolFactory {
    require(newAARS != AARS, "Same safe AAR");
    require(newAARS <= AART, "Safe AAR must be less than or equal to target AAR");
    require(newAARS >= AARC, "Safe AAR must be greater than or equal to circuit breaker AAR");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertAARS(newAARS);

    uint256 prevAARS = AARS;
    AARS = newAARS;
    emit UpdatedAARS(prevAARS, AARS);
  }

  function setAARC(uint256 newAARC) external nonReentrant onlyAssetPoolFactory {
    require(newAARC != AARC, "Same circuit breaker AAR");
    require(newAARC <= AARS, "Circuit breaker AAR must be less than or equal to safe AAR");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertAARC(newAARC);

    uint256 prevAARC = AARC;
    AARC = newAARC;
    emit UpdatedAARC(prevAARC, AARC);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _AAR() internal returns (uint256) {
    uint256 aar = AAR();

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

  function _getAssetTokenPrice() internal view returns (uint256, uint256) {
    uint256 price = IPriceFeed(assetTokenPriceFeed).latestPrice();
    uint256 priceDecimals = IPriceFeed(assetTokenPriceFeed).decimals();

    return (price, priceDecimals);
  }

  function _settleInterest() internal {
    (uint256 newInterestAmount, uint256 totalInterestAmount) = calculateInterest();
    if (newInterestAmount > 0) {
      AssetX(xToken).mint(address(this), newInterestAmount);
    }
    // console.log('_settleInterest, new interest: %s, total: %s', newInterestAmount, totalInterestAmount);

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

  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 usbTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSBFeeCollected(address indexed user, address indexed feeTo, uint256 usbTokenAmount, uint256 feeAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokens(address indexed user, uint256 xTokenAmount, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokensFeeCollected(address indexed user, address indexed feeTo, uint256 xTokenAmount, uint256 fee, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event UsbToXTokens(address indexed user, uint256 usbAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);

  event InterestSettlement(uint256 interestAmount, bool distributed);
}