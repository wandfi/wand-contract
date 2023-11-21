// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IWandProtocol.sol";
import "../interfaces/ILeveragedToken.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IPtyPool.sol";
import "../interfaces/IUSB.sol";
import "../interfaces/IVault.sol";
import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";

contract Vault is IVault, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  IWandProtocol public immutable wandProtocol;
  IProtocolSettings public immutable settings;
  IPtyPool public ptyPoolBelowAARS;
  IPtyPool public ptyPoolAboveAARU;

  address internal immutable _assetToken;
  address internal immutable _assetTokenPriceFeed;
  address internal immutable _usbToken;
  address internal immutable _leveragedToken;

  uint256 internal immutable _settingsDecimals;
  EnumerableSet.Bytes32Set internal _vaultParamsSet;
  mapping(bytes32 => uint256) internal _vaultParams;

  uint256 internal _assetTotalAmount;
  uint256 internal _usbTotalShares;

  // Constants.VaultPhase internal _previousVaultPhase;
  // Constants.VaultPhase internal _vaultPhase;
  Constants.VaultPhase internal _vaultPhase;

  uint256 internal _stableAssetPrice;

  uint256 internal _lastInterestSettlementTime;
  uint256 internal _undistributedInterest;

  uint256 internal _aarBelowSafeLineTime;
  uint256 internal _aarBelowCircuitBreakerLineTime;

  constructor(
    address _wandProtocol,
    address _assetToken_,
    address _assetTokenPriceFeed_,
    address _leveragedToken_,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  )  {
    require(
      _wandProtocol != address(0) && _assetToken_ != address(0) && _assetTokenPriceFeed_ != address(0) && _leveragedToken_ != address(0), 
      "Zero address detected"
    );
    require(assetPoolParams.length == assetPoolParamsValues.length, "Invalid params length");

    wandProtocol = IWandProtocol(_wandProtocol);
    require(msg.sender == wandProtocol.vaultFactory(), "Vault should only be created by factory contract");

    _assetToken = _assetToken_;
    _assetTokenPriceFeed = _assetTokenPriceFeed_;
    _leveragedToken = _leveragedToken_;
    _usbToken = wandProtocol.usbToken();

    settings = IProtocolSettings(IWandProtocol(_wandProtocol).settings());
    _settingsDecimals = settings.decimals();

    for (uint256 i = 0; i < assetPoolParams.length; i++) {
      _updateParam(assetPoolParams[i], assetPoolParamsValues[i]);
    }

    // _vaultPhase = Constants.VaultPhase.Empty;
    // _previousVaultPhase = Constants.VaultPhase.Empty;
    _vaultPhase = Constants.VaultPhase.Empty;
  }

  /* ================= VIEWS ================ */

  function usbToken() public view returns (address) {
    return _usbToken;
  }

  function usbTotalSupply() public view returns (uint256) {
    return IUSB(_usbToken).getBalanceByShares(_usbTotalShares);
  }

  function usbTotalShares() public view returns (uint256) {
    return _usbTotalShares;
  }

  function assetTotalAmount() public view returns (uint256) {
    return _assetTotalAmount;
  }

  function assetToken() public view returns (address) {
    return _assetToken;
  }

  function assetTokenPrice() public view returns (uint256, uint256) {
    (uint256 price, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
    uint256 priceDecimals = IPriceFeed(_assetTokenPriceFeed).decimals();

    return (price, priceDecimals);
  }

  function leveragedToken() public view returns (address) {
    return _leveragedToken;
  }

  function getParamValue(bytes32 param) public view returns (uint256) {
    return _vaultParamValue(param);
  }

  function getVaultPhase() public view returns (Constants.VaultPhase) {
    return _vaultPhase;

    // if (_assetTotalAmount == 0) {
    //   return Constants.VaultPhase.Empty;
    // }

    // uint256 aar = AAR();
    // uint256 AARS = _vaultParamValue("AARS");
    // uint256 AARU = _vaultParamValue("AARU");
    // if (aar < AARS) {
    //   return Constants.VaultPhase.AdjustmentBelowAARS;
    // }
    // else if (aar > AARU) {
    //   return Constants.VaultPhase.AdjustmentAboveAARU;
    // }
    // else {
    //   return Constants.VaultPhase.Stability;
    // }
  }

  /**
   * @notice Current adequency ratio of the pool
   * @dev AAReth = (M_ETH * P_ETH / Musb-eth) * 100%
   */
  function AAR() public view returns (uint256) {
    if (_assetTotalAmount == 0) {
      return 0;
    }
    if (usbTotalSupply() == 0) {
      return type(uint256).max;
    }
    (uint256 _assetTokenPrice, uint256 _assetTokenPriceDecimals) = assetTokenPrice();
    return _assetTotalAmount.mul(_assetTokenPrice).div(10 ** _assetTokenPriceDecimals).mul(10 ** AARDecimals()).div(usbTotalSupply());
  }

  function AARDecimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function calcMintPairsAtStabilityPhase(uint256 assetAmount) public view noneZeroValue(assetAmount) returns (uint256, uint256)  {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.Empty || _vaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    (, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtStabilityPhase(assetAmount);
    return (usbOutAmount, leveragedTokenOutAmount);
  }

  function calcMintPairsAtAdjustmentPhase(uint256 assetAmount) public view noneZeroValue(assetAmount) returns (uint256, uint256) {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || _vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment phase");

    (, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtAdjustmentPhase(assetAmount);
    return (usbOutAmount, leveragedTokenOutAmount);
  }

  function calcMintUsbAboveAARU(uint256 assetAmount) public view noneZeroValue(assetAmount) returns (uint256) {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (, uint256 usbOutAmount) = _calcMintUsbAboveAARU(assetAmount);
    return usbOutAmount;
  }

  function calcMintLeveragedTokensBelowAARS(uint256 assetAmount) noneZeroValue(assetAmount) public view returns (uint256) {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    (, uint256 leveragedTokenOutAmount) = _calcMintLeveragedTokensBelowAARS(assetAmount);
    return leveragedTokenOutAmount;
  }

  function calcPairdLeveragedTokenAmount(uint256 usbAmount) public view noneZeroValue(usbAmount) returns (uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔUSB = ΔETHx * Musb-eth / M_ETHx
    // ΔETHx = ΔUSB * M_ETHx / Musb-eth
    uint256 leveragedTokenOutAmount = usbAmount.mul(S.M_ETHx).div(S.M_USB_ETH);
    return leveragedTokenOutAmount;
  }

  function calcPairedUsbAmount(uint256 leveragedTokenAmount) public view noneZeroValue(leveragedTokenAmount) returns (uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔUSB = ΔETHx * Musb-eth / M_ETHx
    // ΔETHx = ΔUSB * M_ETHx / Musb-eth
    uint256 usbOutAmount = leveragedTokenAmount.mul(S.M_USB_ETH).div(S.M_ETHx);
    return usbOutAmount;
  }

  function calcPairedRedeemAssetAmount(uint256 leveragedTokenAmount) public view noneZeroValue(leveragedTokenAmount) returns (uint256) {
    (, uint256 assetAmount) = _calcPairedRedeemAssetAmount(leveragedTokenAmount);
    return assetAmount;
  }

  function calcRedeemByLeveragedTokenAboveAARU(uint256 leveragedTokenAmount) public view noneZeroValue(leveragedTokenAmount) returns (uint256) {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (, uint256 assetAmount) = _calcRedeemByLeveragedTokenAboveAARU(leveragedTokenAmount);
    return assetAmount;
  }

  function calcRedeemByUsbBelowAARS(uint256 usbAmount) public view noneZeroValue(usbAmount) returns (uint256) {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    (, uint256 assetAmount) = _calcRedeemByUsbBelowAARS(usbAmount);
    return assetAmount;
  }

  function calcUsbToLeveragedTokens(uint256 usbAmount) public view noneZeroValue(usbAmount) returns (uint256) {
    // Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS || _vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment phase");

    (, uint256 leveragedTokenAmount) = _calcUsbToLeveragedTokens(usbAmount);
    return leveragedTokenAmount;
  }

  /* ========== Mint FUNCTIONS ========== */

  function mintPairsAtStabilityPhase(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_vaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    (Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtStabilityPhase(assetAmount);
    _doMint(assetAmount, S, usbOutAmount, leveragedTokenOutAmount);
  }

  function mintPairsAtAdjustmentPhase(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || _vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment phase");

    (Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtAdjustmentPhase(assetAmount);
    _doMint(assetAmount, S, usbOutAmount, leveragedTokenOutAmount);
  }

  function mintUSBAboveAARU(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (Constants.VaultState memory S, uint256 usbOutAmount) = _calcMintUsbAboveAARU(assetAmount);
    _doMint(assetAmount, S, usbOutAmount, 0);
  }

  function mintLeveragedTokensBelowAARS(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    (Constants.VaultState memory S, uint256 leveragedTokenOutAmount) = _calcMintLeveragedTokensBelowAARS(assetAmount);
    _doMint(assetAmount, S, 0, leveragedTokenOutAmount);
  }

   /* ========== Redeem FUNCTIONS ========== */

  function redeemByPairsWithExpectedUSBAmount(uint256 usbAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(usbAmount) {
    require(usbAmount <= IUSB(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    uint256 pairdLeveragedTokenAmount = calcPairdLeveragedTokenAmount(usbAmount);
    require(pairdLeveragedTokenAmount <= ILeveragedToken(_leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcPairedRedeemAssetAmount(pairdLeveragedTokenAmount);
    _doRedeem(assetOutAmount, S, usbAmount, pairdLeveragedTokenAmount);

    emit AssetRedeemedWithPairs(_msgSender(), usbAmount, pairdLeveragedTokenAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function redeemByPairsWithExpectedLeveragedTokenAmount(uint256 leveragedTokenAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(leveragedTokenAmount) {
    require(leveragedTokenAmount <= ILeveragedToken(_leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    uint256 pairedUSBAmount = calcPairedUsbAmount(leveragedTokenAmount);
    require(pairedUSBAmount <= IUSB(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcPairedRedeemAssetAmount(leveragedTokenAmount);
    _doRedeem(assetOutAmount, S, pairedUSBAmount, leveragedTokenAmount);

    emit AssetRedeemedWithPairs(_msgSender(), pairedUSBAmount, leveragedTokenAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function redeemByLeveragedTokenAboveAARU(uint256 leveragedTokenAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(leveragedTokenAmount) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");
    require(leveragedTokenAmount <= ILeveragedToken(_leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcRedeemByLeveragedTokenAboveAARU(leveragedTokenAmount);
    _doRedeem(assetOutAmount, S, 0, leveragedTokenAmount);

    emit AssetRedeemedWithLeveragedToken(_msgSender(), leveragedTokenAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function redeemByUsbBelowAARS(uint256 usbAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(usbAmount) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");
    require(usbAmount <= IUSB(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcRedeemByUsbBelowAARS(usbAmount);
    _doRedeem(assetOutAmount, S, usbAmount, 0);

    emit AssetRedeemedWithUSB(_msgSender(), usbAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  /* ========== Other FUNCTIONS ========== */

  function usbToLeveragedTokens(uint256 usbAmount) external nonReentrant noneZeroValue(usbAmount) doUpdateVaultPhase {  
    require(usbAmount <= IUSB(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS || _vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment phase");

    (Constants.VaultState memory S, uint256 leveragedTokenAmount) = _calcUsbToLeveragedTokens(usbAmount);
    
    uint256 usbSharesAmount = IUSB(_usbToken).burn(_msgSender(), usbAmount);
    _usbTotalShares = _usbTotalShares.sub(usbSharesAmount);
    emit UsbBurned(_msgSender(), usbAmount, usbSharesAmount, S.P_ETH, S.P_ETH_DECIMALS);

    ILeveragedToken(_leveragedToken).mint(_msgSender(), leveragedTokenAmount);
    emit LeveragedTokenMinted(_msgSender(), usbAmount, leveragedTokenAmount, S.P_ETH, S.P_ETH_DECIMALS);

    emit UsbToLeveragedTokens(_msgSender(), usbAmount, leveragedTokenAmount, S.P_ETH, S.P_ETH_DECIMALS);
  }

  function settleInterest() external nonReentrant doSettleInterest {
    // Nothing to do here
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function updateParamValue(bytes32 param, uint256 value) external nonReentrant onlyOwner {
    _updateParam(param, value);
  }

  function setPtyPools(address _ptyPoolBelowAARS, address _ptyPoolAboveAARU) external nonReentrant onlyOwner {
    require(_ptyPoolBelowAARS != address(0) && _ptyPoolAboveAARU != address(0), "Zero address detected");
    require(ptyPoolBelowAARS == IPtyPool(address(0)), "PtyPoolBelowAARS already set");
    require(ptyPoolAboveAARU == IPtyPool(address(0)), "PtyPoolAboveAARU already set");
    require(ptyPoolBelowAARS.vault() == address(this), "Invalid ptyPoolBelowAARS vault to set");
    require(ptyPoolAboveAARU.vault() == address(this), "Invalid ptyPoolAboveAARU vault to set");
    
    ptyPoolBelowAARS = IPtyPool(_ptyPoolBelowAARS);
    ptyPoolAboveAARU = IPtyPool(_ptyPoolAboveAARU);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _updateParam(bytes32 param, uint256 value) internal {
    require(settings.isValidParam(param, value), "Invalid param or value");

    _vaultParamsSet.add(param);
    _vaultParams[param] = value;
    emit UpdateParamValue(param, value);
  }

  function _vaultParamValue(bytes32 param) internal view returns (uint256) {
    require(param.length > 0, "Empty param name");

    if (_vaultParamsSet.contains(param)) {
      return _vaultParams[param];
    }
    return settings.paramDefaultValue(param);
  }

  // 𝑟 = vault.RateR() × 𝑡(h𝑟𝑠), since aar drop below 1.3;
  // r = 0 since aar above 2;
  function _r(Constants.VaultState memory S) internal view returns (uint256) {
    if (_aarBelowSafeLineTime == 0) {
      return 0;
    }
    return S.RateR.mul(block.timestamp.sub(S.aarBelowSafeLineTime)).div(1 hours);
  }

  function _getVaultState() internal view returns (Constants.VaultState memory) {
    Constants.VaultState memory S;
    S.P_ETH_i = _stableAssetPrice;
    S.M_ETH = _assetTotalAmount;
    (S.P_ETH, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
    S.P_ETH_DECIMALS = IPriceFeed(_assetTokenPriceFeed).decimals();
    S.M_USB_ETH = usbTotalSupply();
    S.M_ETHx = IERC20(_leveragedToken).totalSupply();
    S.aar = AAR();
    S.AART = _vaultParamValue("AART");
    S.AARS = _vaultParamValue("AARS");
    S.AARU = _vaultParamValue("AARU");
    S.AARC = _vaultParamValue("AARC");
    S.AARDecimals = AARDecimals();
    S.RateR = _vaultParamValue("RateR");
    S.BasisR = _vaultParamValue("BasisR");
    S.BasisR2 = _vaultParamValue("BasisR2");
    S.aarBelowSafeLineTime = _aarBelowSafeLineTime;
    S.settingsDecimals = _settingsDecimals;

    return S;
  }

  function _calcMintPairsAtStabilityPhase(uint256 assetAmount) internal view returns (Constants.VaultState memory, uint256, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔUSB = ΔETH * P_ETH_i * 1 / AART_eth
    // ΔETHx = ΔETH * (1 - 1 / AART_eth) = ΔETH * (AART_eth - 1) / AART_eth
    uint256 usbOutAmount = assetAmount.mul(S.P_ETH_i).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AART);
    uint256 leveragedTokenOutAmount = assetAmount.mul(
      (S.AART).sub(10 ** S.AARDecimals)
    ).div(S.AART);
    return (S, usbOutAmount, leveragedTokenOutAmount);
  }

  function _calcMintPairsAtAdjustmentPhase(uint256 assetAmount) internal view returns (Constants.VaultState memory, uint256, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔUSB = ΔETH * P_ETH * 1 / AAR
    // ΔETHx = ΔETH * P_ETH * M_ETHx / (AAR * Musb-eth)
    Constants.Terms memory T;
    T.T1 = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    uint256 usbOutAmount = T.T1.mul(10 ** S.AARDecimals).div(S.aar);
    uint256 leveragedTokenOutAmount = T.T1
      .mul(S.M_ETHx).mul(10 ** S.AARDecimals).div(S.aar).div(S.M_USB_ETH);
    return (S, usbOutAmount, leveragedTokenOutAmount);
  }

  function _calcMintUsbAboveAARU(uint256 assetAmount) internal view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔUSB = ΔETH * P_ETH
    uint256 usbOutAmount = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    return (S, usbOutAmount);
  }

  function _calcMintLeveragedTokensBelowAARS(uint256 assetAmount) internal view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔETHx = ΔETH * P_ETH * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    uint256 leveragedTokenOutAmount = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(S.M_ETHx).div(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    );
    return (S, leveragedTokenOutAmount);
  }

  function _calcPairedRedeemAssetAmount(uint256 leveragedTokenAmount) internal view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔETH = ΔETHx * M_ETH / M_ETHx
    uint256 assetOutAmount = leveragedTokenAmount.mul(S.M_ETH).div(S.M_ETHx);
    return (S, assetOutAmount);
  }

  function _calcRedeemByLeveragedTokenAboveAARU(uint256 leveragedTokenAmount) internal view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔETH = ΔETHx * (M_ETH * P_ETH - Musb-eth) / (M_ETHx * P_ETH)
    uint256 assetOutAmount = leveragedTokenAmount.mul(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    ).div(S.M_ETHx.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS));
    return (S, assetOutAmount);
  }

  function _calcRedeemByUsbBelowAARS(uint256 usbAmount) internal view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = _getVaultState();

    if (S.aar < (10 ** S.AARDecimals)) {
      // ΔETH = ΔUSB * M_ETHx / Musb-eth
      uint256 assetOutAmount = usbAmount.mul(S.M_ETHx).div(S.M_USB_ETH);
      return (S, assetOutAmount);
    }
    else {
      // ΔETH = ΔUSB / P_ETH
      uint256 assetOutAmount = usbAmount.mul(10 ** S.P_ETH_DECIMALS).div(S.P_ETH);
      return (S, assetOutAmount);
    }
  }

  function _calcUsbToLeveragedTokens(uint256 usbAmount) internal view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = _getVaultState();

    // ΔETHx = ΔUSB * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth)
    uint256 leveragedTokenOutAmount = usbAmount.mul(S.M_ETHx).mul((10 ** S.settingsDecimals).add(_r(S))).div(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    );
    return (S, leveragedTokenOutAmount);
  }

  function _doMint(uint256 assetAmount, Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) internal {
    _assetTotalAmount = _assetTotalAmount.add(assetAmount);
    TokensTransfer.transferTokens(_assetToken, _msgSender(), address(this), assetAmount);

    if (usbOutAmount > 0) {
      uint256 usbSharesAmount = IUSB(_usbToken).mint(_msgSender(), usbOutAmount);
      _usbTotalShares = _usbTotalShares.add(usbSharesAmount);
      emit UsbMinted(_msgSender(), assetAmount, usbOutAmount, usbSharesAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }

    if (leveragedTokenOutAmount > 0) {
      ILeveragedToken(_leveragedToken).mint(_msgSender(), leveragedTokenOutAmount);
      emit LeveragedTokenMinted(_msgSender(), assetAmount, leveragedTokenOutAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }
  }

  function _doRedeem(uint256 assetAmount, Constants.VaultState memory S, uint256 usbAmount, uint256 leveragedTokenAmount) internal {
    require(assetAmount <= _assetTotalAmount, "Not enough asset balance");
    _assetTotalAmount = _assetTotalAmount.sub(assetAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), _msgSender(), assetAmount);

    if (usbAmount > 0) {
      uint256 usbBurnShares = IUSB(_usbToken).burn(_msgSender(), usbAmount);
      _usbTotalShares = _usbTotalShares.sub(usbBurnShares);
      emit UsbBurned(_msgSender(), usbAmount, usbBurnShares, S.P_ETH, S.P_ETH_DECIMALS);
    }

    if (leveragedTokenAmount > 0) {
      ILeveragedToken(_leveragedToken).burn(_msgSender(), leveragedTokenAmount);
      emit LeveragedTokenBurned(_msgSender(), leveragedTokenAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }
  }

  function _ptyPoolMatchBelowAARS() internal {
    Constants.VaultState memory S = _getVaultState();

    // ΔETH = (Musb-eth * AART - M_ETH * P_ETH) / (P_ETH * (AART - 1))
    // uint256 deltaAssetAmount = S.M_USB_ETH.mul(S.AART).mul(10 ** S.P_ETH_DECIMALS).sub(
    //   S.M_ETH.mul(S.P_ETH)
    // ).div(
    //   S.P_ETH.mul(S.AART.sub(10 ** S.AARDecimals))
    // ).div(10 ** S.P_ETH_DECIMALS).div(10 ** S.AARDecimals);

    // ΔUSB = (Musb-eth * AART - M_ETH * P_ETH) / (AART - 1)
    uint256 deltaUsbAmount = S.M_USB_ETH.mul(S.AART).sub(
      S.M_ETH.mul(S.P_ETH).mul(10 ** S.AARDecimals).div(10 ** S.P_ETH_DECIMALS)
    ).div(S.AART.sub(10 ** S.AARDecimals)).div(10 ** S.AARDecimals);

    uint256 minUsbAmount = _vaultParamValue("PtyPoolMinUsbAmount");
    uint256 ptyPoolUsbBalance = IERC20(_usbToken).balanceOf(address(ptyPoolBelowAARS));
    if (deltaUsbAmount >= ptyPoolUsbBalance || deltaUsbAmount + minUsbAmount >= ptyPoolUsbBalance) {
      deltaUsbAmount = ptyPoolUsbBalance;
    }

    // do redeem for the PtyPool
    uint256 deltaAssetAmount = deltaUsbAmount.mul(10 ** S.P_ETH_DECIMALS).div(S.P_ETH);
    _assetTotalAmount = _assetTotalAmount.sub(deltaAssetAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolBelowAARS), deltaAssetAmount);
    uint256 usbBurnShares = IUSB(_usbToken).burn(address(ptyPoolBelowAARS), deltaUsbAmount);
    _usbTotalShares = _usbTotalShares.sub(usbBurnShares);
    emit UsbBurned(address(ptyPoolBelowAARS), deltaUsbAmount, usbBurnShares, S.P_ETH, S.P_ETH_DECIMALS);
    ptyPoolBelowAARS.notifyMatchedBelowAARS(deltaAssetAmount);
  }

  function _ptyPoolMatchAboveAARU() internal {

  }

  /* ============== MODIFIERS =============== */

  modifier onlyOwner() {
    require(_msgSender() == wandProtocol.protocolOwner(), "Caller is not owner");
    _;
  }

  modifier noneZeroValue(uint256 value) {
    require(value > 0, "Value must be greater than 0");
    _;
  }

  modifier noneZeroAddress(address addr) {
    require(addr != address(0), "Zero address detected");
    _;
  }

  modifier doUpdateVaultPhase() {
    // _vaultPhase = getVaultPhase();
    // // Initial Empty => Empty
    // if (_previousVaultPhase == Constants.VaultPhase.Empty && _vaultPhase == Constants.VaultPhase.Empty) {
    //   (_stableAssetPrice, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
    // }
    // // Empty/AboveAARU/BelowAARS => Stable
    // else if (_previousVaultPhase != Constants.VaultPhase.Stability && _vaultPhase == Constants.VaultPhase.Stability) {
    //   (_stableAssetPrice, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
    // }
    // else {
    //   // Clear to prevent incautious usage
    //   _stableAssetPrice = 0;
    // }

    // Constants.VaultPhase nextVaultPhase = getVaultPhase();
    // if (_vaultPhase != Constants.VaultPhase.AdjustmentBelowAARS && nextVaultPhase == Constants.VaultPhase.AdjustmentBelowAARS) {
    //   require(ptyPoolBelowAARS != IPtyPool(address(0)), "PtyPoolBelowAARS not set");
    //   if (ptyPoolBelowAARS.totalStakingBalance() > 0) {
    //     _ptyPoolMatchBelowAARS();
    //     _previousVaultPhase = nextVaultPhase;
    //   }
    // }
    // else if (_vaultPhase != Constants.VaultPhase.AdjustmentAboveAARU && nextVaultPhase == Constants.VaultPhase.AdjustmentAboveAARU) {
    //   require(ptyPoolAboveAARU != IPtyPool(address(0)), "PtyPoolAboveAARU not set");
    //   if (ptyPoolAboveAARU.totalStakingBalance() > 0) {
    //     _ptyPoolMatchAboveAARU();
    //     _previousVaultPhase = nextVaultPhase;
    //   }
    // }

    uint256 previousAAR = AAR();
    if (_vaultPhase == Constants.VaultPhase.Empty) {
      (_stableAssetPrice, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
    }
    _vaultPhase = Constants.VaultPhase.Stability;
    Constants.VaultPhase previousPhase = _vaultPhase;

    _;

    uint256 afterAAR = AAR();
    uint256 AART = _vaultParamValue("AART");
    uint256 AARS = _vaultParamValue("AARS");
    uint256 AARU = _vaultParamValue("AARU");
    if (previousPhase == Constants.VaultPhase.Stability) {
      if (afterAAR > AARU) {
        _vaultPhase = Constants.VaultPhase.AdjustmentAboveAARU;
      }
      else if (afterAAR < AARS) {
        _vaultPhase = Constants.VaultPhase.AdjustmentBelowAARS;
        _aarBelowSafeLineTime = block.timestamp;
      }
    }
    else if (previousPhase == Constants.VaultPhase.AdjustmentBelowAARS) {
      if (afterAAR > AART) {
        _vaultPhase = Constants.VaultPhase.Stability;
        (_stableAssetPrice, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
        _aarBelowSafeLineTime = 0;
      }
    }
    else if (previousPhase == Constants.VaultPhase.AdjustmentAboveAARU) {
      if (afterAAR < AART) {
        _vaultPhase = Constants.VaultPhase.Stability;
        (_stableAssetPrice, ) = IPriceFeed(_assetTokenPriceFeed).latestPrice();
      }
    }

    if (afterAAR < AARS) {
      require(ptyPoolBelowAARS != IPtyPool(address(0)), "PtyPoolBelowAARS not set");
      if (ptyPoolBelowAARS.totalStakingBalance() > 0) {
        _ptyPoolMatchBelowAARS();
      }
    }
    else if (afterAAR > AARU) {
      require(ptyPoolAboveAARU != IPtyPool(address(0)), "PtyPoolAboveAARU not set");
      if (ptyPoolAboveAARU.totalStakingBalance() > 0) {
        _ptyPoolMatchAboveAARU();
      }
    }

    // _previousVaultPhase = _vaultPhase;
  }

  modifier doSettleInterest() {
    // _settleInterest();
    _;
    // _startOrPauseInterestGeneration();
  }

  /* =============== EVENTS ============= */

  event UpdateParamValue(bytes32 indexed param, uint256 value);
  
  event UsbMinted(address indexed user, uint256 assetTokenAmount, uint256 usbTokenAmount, uint256 usbSharesAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event LeveragedTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event UsbBurned(address indexed user, uint256 usbTokenAmount, uint256 usbSharesAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event LeveragedTokenBurned(address indexed user, uint256 leveragedTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithPairs(address indexed user, uint256 usbAmount, uint256 leveragedTokenAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithLeveragedToken(address indexed user, uint256 leveragedTokenAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event UsbToLeveragedTokens(address indexed user, uint256 usbAmount, uint256 leveragedTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);

  event InterestSettlement(uint256 interestAmount, bool distributed);
}