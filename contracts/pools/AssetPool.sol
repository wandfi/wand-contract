// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IAssetPool.sol";
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

  uint256 private _usbTotalSupply;

  uint256 private immutable _settingsDecimals;
  uint256 private _redemptionFeeWithUSBTokens;
  uint256 private _redemptionFeeWithXTokens;

  constructor(
    address _wandProtocol,
    address _assetPoolFactory,
    address _assetToken,
    address _assetTokenPriceFeed,
    address _usbToken,
    string memory _xTokenName,
    string memory _xTokenSymbol
  ) {
    require(_wandProtocol != address(0), "Zero address detected");
    require(_assetPoolFactory != address(0), "Zero address detected");
    require(_assetToken != address(0), "Zero address detected");
    require(_assetTokenPriceFeed != address(0), "Zero address detected");
    require(_usbToken != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
    assetPoolFactory = _assetPoolFactory;
    assetToken = _assetToken;
    assetTokenPriceFeed = _assetTokenPriceFeed;
    usbToken = _usbToken;
    xToken = address(new AssetX(address(this), _xTokenName, _xTokenSymbol));

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    _settingsDecimals = settings.settingDecimals();
    _redemptionFeeWithUSBTokens = settings.defaultRedemptionFeeWithUSBTokens();
    _redemptionFeeWithXTokens = settings.defaultRedemptionFeeWithXTokens();
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
  function currentAssetAdequencyRatio() public view returns (uint256) {
    uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
    require(xTokenTotalAmount > 0, "No x token minted yet");

    uint256 assetTotalAmount = _getAssetTotalAmount();
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** Constants.PROTOCOL_DECIMALS).div(xTokenTotalAmount);
  }

  function currentAssetAdequencyRatioDecimals() public pure returns (uint256) {
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
   * @dev Δusb = Δeth * Peth
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintUSB(uint256 assetAmount) external payable override nonReentrant {
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    uint256 tokenAmount = assetAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals);

    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);
    USB(usbToken).mint(_msgSender(), tokenAmount);
    _usbTotalSupply = _usbTotalSupply.add(tokenAmount);

    emit USBMinted(_msgSender(), assetAmount, assetTokenPrice, assetTokenPriceDecimals, tokenAmount);
  }

  /**
   * @notice Mint X tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintXTokens(uint256 assetAmount) external payable override nonReentrant {
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
  function redeemByUSB(uint256 usbAmount) external override nonReentrant {
    require(usbAmount > 0, "Amount must be greater than 0");

    uint256 assetAmount = 0;

    uint256 aar = currentAssetAdequencyRatio();
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();

    // if AAR >= 100%,  Δeth = (Δusb / Peth) * (1 -C1)
    if (aar >= 10 ** currentAssetAdequencyRatioDecimals()) {
      assetAmount = usbAmount.mul(10 ** assetTokenPriceDecimals).div(assetTokenPrice).mul(
        (10 ** _settingsDecimals).sub(_redemptionFeeWithUSBTokens)
      ).div(10 ** _settingsDecimals);
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
  }

  /**
   * @notice Redeem asset tokens with X tokens
   * @param xTokenAmount: Amount of X tokens used to redeem for asset tokens
   */
  function redeemByXTokens(uint256 xTokenAmount) external override nonReentrant {
    uint256 pairedUSBAmount = pairedUSBAmountToDedeemByXTokens(xTokenAmount);

    // Δeth = Δethx * Meth / Methx * (1 -C2)
    uint256 assetAmount = xTokenAmount.mul(_getAssetTotalAmount()).div(AssetX(xToken).totalSupply()).mul(
      (10 ** _settingsDecimals).sub(_redemptionFeeWithXTokens)
    ).div(10 ** _settingsDecimals);

    USB(usbToken).burn(_msgSender(), pairedUSBAmount);
    _usbTotalSupply = _usbTotalSupply.sub(pairedUSBAmount);
    AssetX(xToken).burn(_msgSender(), xTokenAmount);
    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);

    emit AssetRedeemedWithXTokens(_msgSender(), xTokenAmount, pairedUSBAmount, assetAmount);
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function setRedemptionFeeWithUSBTokens(uint256 newRedemptionFeeWithUSBTokens) external nonReentrant onlyAssetPoolFactory {
    require(newRedemptionFeeWithUSBTokens != _redemptionFeeWithUSBTokens, "Same redemption fee");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertRedemptionFeeWithUSBTokens(newRedemptionFeeWithUSBTokens);
    
    _redemptionFeeWithUSBTokens = newRedemptionFeeWithUSBTokens;
    emit RedemptionFeeWithUSBTokensUpdated(_redemptionFeeWithUSBTokens, newRedemptionFeeWithUSBTokens);
  }

  function setRedemptionFeeWithXTokens(uint256 newRedemptionFeeWithXTokens) external nonReentrant onlyAssetPoolFactory {
    require(newRedemptionFeeWithXTokens != _redemptionFeeWithXTokens, "Same redemption fee");

    IProtocolSettings settings = IProtocolSettings(WandProtocol(wandProtocol).settings());
    settings.assertRedemptionFeeWithXTokens(newRedemptionFeeWithXTokens);

    _redemptionFeeWithXTokens = newRedemptionFeeWithXTokens;
    emit RedemptionFeeWithXTokensUpdated(_redemptionFeeWithXTokens, newRedemptionFeeWithXTokens);
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

  /* ============== MODIFIERS =============== */

  modifier onlyAssetPoolFactory() {
    require(_msgSender() == assetPoolFactory, "Caller is not AssetPoolFactory");
    _;
  }

  /* =============== EVENTS ============= */

  event RedemptionFeeWithUSBTokensUpdated(uint256 prevRedemptionFeeWithUSBTokens, uint256 newDefaultRedemptionFeeWithUSBTokens);
  event RedemptionFeeWithXTokensUpdated(uint256 prevRedemptionFeeWithXTokens, uint256 newDefaultRedemptionFeeWithXTokens);

  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 usbTokenAmount);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 xTokenAmount);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithXTokens(address indexed user, uint256 xTokenAmount, uint256 pairedUSBAmount, uint256 assetAmount);
}