// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IPriceFeed.sol";
import "../interfaces/IAssetPool.sol";
import "../libs/Constants.sol";
import "../tokens/AssetX.sol";
import "../tokens/USB.sol";

contract AssetPool is IAssetPool, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // address public immutable assetPoolFactory;
  address public immutable assetToken;
  address public immutable assetTokenPriceFeed;
  address public immutable usbToken;
  address public immutable xToken;

  uint256 private _usbTotalSupply;

  constructor(
    // address _assetPoolFactory,
    address _assetToken,
    address _assetTokenPriceFeed,
    address _usbToken,
    string memory _xTokenName,
    string memory _xTokenSymbol
  ) {
    // require(_assetPoolFactory != address(0), "Zero address detected");
    require(_assetToken != address(0), "Zero address detected");
    require(_assetTokenPriceFeed != address(0), "Zero address detected");
    require(_usbToken != address(0), "Zero address detected");
    // assetPoolFactory = _assetPoolFactory;
    assetToken = _assetToken;
    assetTokenPriceFeed = _assetTokenPriceFeed;
    usbToken = _usbToken;
    xToken = address(new AssetX(address(this), _xTokenName, _xTokenSymbol));
  }

  /* ================= VIEWS ================ */

  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() public view returns (uint256) {
    return _usbTotalSupply;
  }

  /**
   * @notice Current adequency ratio of the pool, with 18 decimals
   * @dev AAReth = (Meth * Peth / Musb-eth) * 100%
   */
  function currentAssetAdequencyRatio() public view returns (uint256) {
    uint256 xTokenTotalAmount = AssetX(xToken).totalSupply();
    require(xTokenTotalAmount > 0, "No x token minted yet");

    uint256 assetTotalAmount = _getAssetTotalAmount();
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(1e18).div(xTokenTotalAmount);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * @notice Mint $USB tokens using asset token
   * @dev Δusb = Δeth * Peth
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintUSB(uint256 assetAmount) external payable override nonReentrant {
    _transferAssetTokens(assetAmount);

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = _getAssetTokenPrice();
    uint256 tokenAmount = assetAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals);
    USB(usbToken).mint(_msgSender(), tokenAmount);
    _usbTotalSupply = _usbTotalSupply.add(tokenAmount);

    emit USBMinted(_msgSender(), assetAmount, assetTokenPrice, assetTokenPriceDecimals, tokenAmount);
  }

  /**
   * @notice Mint X tokens using asset token
   * @param assetAmount: Amount of asset token used to mint
   */
  function mintXTokens(uint256 assetAmount) external payable override nonReentrant {
    _transferAssetTokens(assetAmount);

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

    AssetX(xToken).mint(_msgSender(), xTokenAmount);
    emit XTokenMinted(_msgSender(), assetAmount, assetTokenPrice, assetTokenPriceDecimals, xTokenAmount);
  }

  /**
   * @notice Redeem asset tokens with $USB
   * @param usbAmount: Amount of $USB tokens used to redeem for asset tokens
   */
  function redeemByUSB(uint256 usbAmount) external override nonReentrant {

  }

  /**
   * @notice Redeem asset tokens with X tokens
   * @param xTokenAmount: Amount of X tokens used to redeem for asset tokens
   */
  function redeemByXTokens(uint256 xTokenAmount) external override nonReentrant {

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

  function _transferAssetTokens(uint256 amount) internal {
    require(amount > 0, "Amount must be greater than 0");

    if (assetToken == Constants.NATIVE_TOKEN) {
      require(msg.value == amount, "Incorrect msg.value");
    }
    else {
      IERC20(assetToken).safeTransferFrom(_msgSender(), address(this), amount);
    }
  }

  /* ============== MODIFIERS =============== */

  // modifier onlyAssetPoolFactory() {
  //   require(msg.sender == assetPoolFactory, "Caller is not AssetPoolFactory");
  //   _;
  // }

  /* =============== EVENTS ============= */

  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 usbTokenAmount);
  event XTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals, uint256 xTokenAmount);

}