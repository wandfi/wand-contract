// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IWandProtocol.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultCalculator.sol";
import "../interfaces/IInterestPoolFactory.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IUSB.sol";
import "../interfaces/ILeveragedToken.sol";
import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";

contract Vault is IVault, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  IWandProtocol public immutable wandProtocol;
  IProtocolSettings public immutable settings;
  address public immutable vaultCalculator;
  address public immutable assetToken;
  address public immutable assetTokenPriceFeed;
  address public immutable usbToken;
  address public immutable leveragedToken;

  uint256 internal immutable settingsDecimals;
  EnumerableSet.Bytes32Set internal _vaultParamsSet;
  mapping(bytes32 => uint256) internal _vaultParams;

  uint256 internal _assetTotalAmount;
  uint256 internal _usbTotalShares;

  Constants.VaultPhase internal _currentVaultPhase;
  Constants.VaultPhase internal _lastCheckedVaultPhase;
  uint256 internal _stableAssetPrice;

  uint256 internal _lastInterestSettlementTime;
  uint256 internal _undistributedInterest;

  uint256 internal _aarBelowSafeLineTime;
  uint256 internal _aarBelowCircuitBreakerLineTime;

  constructor(
    address _wandProtocol,
    address _assetToken,
    address _assetTokenPriceFeed,
    address _leveragedToken,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  )  {
    require(
      _wandProtocol != address(0) && _assetToken != address(0) && _assetTokenPriceFeed != address(0) && _leveragedToken != address(0), 
      "Zero address detected"
    );
    require(assetPoolParams.length == assetPoolParamsValues.length, "Invalid params length");

    wandProtocol = IWandProtocol(_wandProtocol);
    require(msg.sender == wandProtocol.vaultFactory(), "Vault should only be created by factory contract");

    assetToken = _assetToken;
    assetTokenPriceFeed = _assetTokenPriceFeed;
    leveragedToken = _leveragedToken;
    vaultCalculator = wandProtocol.vaultCalculator();
    usbToken = wandProtocol.usbToken();

    settings = IProtocolSettings(IWandProtocol(_wandProtocol).settings());
    settingsDecimals = settings.decimals();

    for (uint256 i = 0; i < assetPoolParams.length; i++) {
      _updateParam(assetPoolParams[i], assetPoolParamsValues[i]);
    }
  }

  /* ================= VIEWS ================ */

  function usbTotalSupply() public view returns (uint256) {
    return IUSB(usbToken).getBalanceByShares(_usbTotalShares);
  }

  function usbTotalShares() public view returns (uint256) {
    return _usbTotalShares;
  }

  function getAssetTotalAmount() public view returns (uint256) {
    return _assetTotalAmount;
  }

  function getAssetToken() public view returns (address) {
    return assetToken;
  }

  function getAssetTokenPrice() public view returns (uint256, uint256) {
    (uint256 price, ) = IPriceFeed(assetTokenPriceFeed).latestPrice();
    uint256 priceDecimals = IPriceFeed(assetTokenPriceFeed).decimals();

    return (price, priceDecimals);
  }

  function getParamValue(bytes32 param) public view returns (uint256) {
    return _vaultParamValue(param);
  }

  function getVaultPhase() public view returns (Constants.VaultPhase) {
    if (_assetTotalAmount == 0) {
      return Constants.VaultPhase.Empty;
    }

    uint256 aar = AAR();
    uint256 AARS = _vaultParamValue("AARS");
    uint256 AARU = _vaultParamValue("AARU");
    if (aar < AARS) {
      return Constants.VaultPhase.AdjustmentBelowAARS;
    }
    else if (aar > AARU) {
      return Constants.VaultPhase.AdjustmentAboveAARU;
    }
    else {
      return Constants.VaultPhase.Stability;
    }
  }

  /**
   * @notice Current adequency ratio of the pool
   * @dev AAReth = (M_ETH * P_ETH / Musb-eth) * 100%
   */
  function AAR() public view returns (uint256) {
    return IVaultCalculator(vaultCalculator).AAR(IVault(this));
  }

  function AARDecimals() public pure returns (uint256) {
    return Constants.PROTOCOL_DECIMALS;
  }

  function calcMintPairsAtStabilityPhase(uint256 assetAmount) public view noneZeroValue(assetAmount) returns (uint256, uint256)  {
    Constants.VaultPhase vaultPhase = getVaultPhase();
    require(vaultPhase == Constants.VaultPhase.Empty || vaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    (, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtStabilityPhase(assetAmount);
    return (usbOutAmount, leveragedTokenOutAmount);
  }

  function calcMintPairsAtAdjustmentPhase(uint256 assetAmount) public view noneZeroValue(assetAmount) returns (uint256, uint256) {
    Constants.VaultPhase vaultPhase = getVaultPhase();
    require(_currentVaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || _currentVaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment phase");

    (, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtAdjustmentPhase(assetAmount);
    return (usbOutAmount, leveragedTokenOutAmount);
  }

  function calcMintUSBAboveAARU(uint256 assetAmount) public view noneZeroValue(assetAmount) returns (uint256) {
    Constants.VaultPhase vaultPhase = getVaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (, uint256 usbOutAmount) = _calcMintUSBAboveAARU(assetAmount);
    return usbOutAmount;
  }

  function calcMintLeveragedTokensBelowAARS(uint256 assetAmount) noneZeroValue(assetAmount) public view returns (uint256) {
    Constants.VaultPhase vaultPhase = getVaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

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

  function calcPairedUSBAmount(uint256 leveragedTokenAmount) public view noneZeroValue(leveragedTokenAmount) returns (uint256) {
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
    Constants.VaultPhase vaultPhase = getVaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (, uint256 assetAmount) = _calcRedeemByLeveragedTokenAboveAARU(leveragedTokenAmount);
    return assetAmount;
  }

  function calcRedeemByUSBBelowAARS(uint256 usbAmount) public view noneZeroValue(usbAmount) returns (uint256) {
    Constants.VaultPhase vaultPhase = getVaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    (, uint256 assetAmount) = _calcRedeemByUSBBelowAARS(usbAmount);
    return assetAmount;
  }

  /* ========== Mint FUNCTIONS ========== */

  function mintPairsAtStabilityPhase(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_currentVaultPhase == Constants.VaultPhase.Empty || _currentVaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    (Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtStabilityPhase(assetAmount);
    _doMint(assetAmount, S, usbOutAmount, leveragedTokenOutAmount);
  }

  function mintPairsAtAdjustmentPhase(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_currentVaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || _currentVaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment phase");

    (Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = _calcMintPairsAtAdjustmentPhase(assetAmount);
    _doMint(assetAmount, S, usbOutAmount, leveragedTokenOutAmount);
  }

  function mintUSBAboveAARU(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_currentVaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (Constants.VaultState memory S, uint256 usbOutAmount) = _calcMintUSBAboveAARU(assetAmount);
    _doMint(assetAmount, S, usbOutAmount, 0);
  }

  function mintLeveragedTokensBelowAARS(uint256 assetAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(assetAmount) {
    require(_currentVaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    (Constants.VaultState memory S, uint256 leveragedTokenOutAmount) = _calcMintLeveragedTokensBelowAARS(assetAmount);
    _doMint(assetAmount, S, 0, leveragedTokenOutAmount);
  }

   /* ========== Redeem FUNCTIONS ========== */

  function redeemByPairsWithExpectedUSBAmount(uint256 usbAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(usbAmount) {
    require(usbAmount <= IUSB(usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    uint256 pairdLeveragedTokenAmount = calcPairdLeveragedTokenAmount(usbAmount);
    require(pairdLeveragedTokenAmount <= ILeveragedToken(leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcPairedRedeemAssetAmount(pairdLeveragedTokenAmount);
    _doRedeem(assetOutAmount, S, usbAmount, pairdLeveragedTokenAmount);

    emit AssetRedeemedWithPairs(_msgSender(), usbAmount, pairdLeveragedTokenAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function redeemByPairsWithExpectedLeveragedTokenAmount(uint256 leveragedTokenAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(leveragedTokenAmount) {
    require(leveragedTokenAmount <= ILeveragedToken(leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    uint256 pairedUSBAmount = calcPairedUSBAmount(leveragedTokenAmount);
    require(pairedUSBAmount <= IUSB(usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcPairedRedeemAssetAmount(leveragedTokenAmount);
    _doRedeem(assetOutAmount, S, pairedUSBAmount, leveragedTokenAmount);

    emit AssetRedeemedWithPairs(_msgSender(), pairedUSBAmount, leveragedTokenAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function redeemByLeveragedTokenAboveAARU(uint256 leveragedTokenAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(leveragedTokenAmount) {
    require(_currentVaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");
    require(leveragedTokenAmount <= ILeveragedToken(leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcRedeemByLeveragedTokenAboveAARU(leveragedTokenAmount);
    _doRedeem(assetOutAmount, S, 0, leveragedTokenAmount);

    emit AssetRedeemedWithLeveragedToken(_msgSender(), leveragedTokenAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function redeemByUSBBelowAARS(uint256 usbAmount) external payable nonReentrant doUpdateVaultPhase noneZeroValue(usbAmount) {
    require(_currentVaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");
    require(usbAmount <= IUSB(usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = _calcRedeemByUSBBelowAARS(usbAmount);
    _doRedeem(assetOutAmount, S, usbAmount, 0);
    
    emit AssetRedeemedWithUSB(_msgSender(), usbAmount, assetOutAmount, S.P_ETH, S.P_ETH_DECIMALS);

    // TODO: fee
  }

  function checkAAR() external nonReentrant doCheckAAR {
    // Nothing to do here
  }

  function settleInterest() external nonReentrant doCheckAAR doSettleInterest {
    // Nothing to do here
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function updateParamValue(bytes32 param, uint256 value) external nonReentrant onlyOwner {
    _updateParam(param, value);
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

  function _AAR() internal returns (uint256) {
    uint256 aar = AAR();

    uint256 AARS = _vaultParamValue("AARS");
    uint256 AARC = _vaultParamValue("AARC");
    // console.log('_AAR, _aarBelowSafeLineTime: %s, aar: %s, AARC: %s', _aarBelowSafeLineTime, aar, AARC);
    if (_aarBelowSafeLineTime == 0) {
      if (aar < AARS) {
        _aarBelowSafeLineTime = block.timestamp;
      }
    } else if (aar >= AARS) {
      _aarBelowSafeLineTime = 0;
    }
    // console.log('_AAR after, _aarBelowSafeLineTime: %s', _aarBelowSafeLineTime);

    // console.log('_AAR, _aarBelowCircuitBreakerLineTime: %s, aar: %s, AARC: %s', _aarBelowCircuitBreakerLineTime, aar, AARC);
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

  function _getVaultState() internal view returns (Constants.VaultState memory) {
    Constants.VaultState memory S;
    S.P_ETH_i = _stableAssetPrice;
    S.M_ETH = _assetTotalAmount;
    (S.P_ETH, ) = IPriceFeed(assetTokenPriceFeed).latestPrice();
    S.P_ETH_DECIMALS = IPriceFeed(assetTokenPriceFeed).decimals();
    S.M_USB_ETH = usbTotalSupply();
    S.M_ETHx = IERC20(leveragedToken).totalSupply();
    S.aar = IVaultCalculator(vaultCalculator).AAR(IVault(this));
    S.AART = _vaultParamValue("AART");
    S.AARS = _vaultParamValue("AARS");
    S.AARU = _vaultParamValue("AARU");
    S.AARC = _vaultParamValue("AARC");
    S.AARDecimals = AARDecimals();
    S.RateR = _vaultParamValue("RateR");
    S.BasisR = _vaultParamValue("BasisR");
    S.BasisR2 = _vaultParamValue("BasisR2");
    S.aarBelowSafeLineTime = _aarBelowSafeLineTime;
    S.settingsDecimals = settingsDecimals;

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
    uint256 usbOutAmount = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.aar);
    uint256 leveragedTokenOutAmount = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS)
      .mul(S.M_ETHx).mul(10 ** S.AARDecimals).div(S.aar).div(S.M_USB_ETH);
    return (S, usbOutAmount, leveragedTokenOutAmount);
  }

  function _calcMintUSBAboveAARU(uint256 assetAmount) internal view returns (Constants.VaultState memory, uint256) {
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

  function _calcRedeemByUSBBelowAARS(uint256 usbAmount) internal view returns (Constants.VaultState memory, uint256) {
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

  function _doMint(uint256 assetAmount, Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) internal {
    _assetTotalAmount = _assetTotalAmount.add(assetAmount);
    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);

    if (usbOutAmount > 0) {
      uint256 usbSharesAmount = IUSB(usbToken).mint(_msgSender(), usbOutAmount);
      _usbTotalShares = _usbTotalShares.add(usbSharesAmount);
      emit USBMinted(_msgSender(), assetAmount, usbOutAmount, usbSharesAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }

    if (leveragedTokenOutAmount > 0) {
      ILeveragedToken(leveragedToken).mint(_msgSender(), leveragedTokenOutAmount);
      emit LeveragedTokenMinted(_msgSender(), assetAmount, leveragedTokenOutAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }
  }

  function _doRedeem(uint256 assetAmount, Constants.VaultState memory S, uint256 usbAmount, uint256 leveragedTokenAmount) internal {
    _assetTotalAmount = _assetTotalAmount.add(assetAmount);
    TokensTransfer.transferTokens(assetToken, _msgSender(), address(this), assetAmount);

    require(assetAmount <= _assetTotalAmount, "Not enough asset balance");
    _assetTotalAmount = _assetTotalAmount.sub(assetAmount);
    TokensTransfer.transferTokens(assetToken, address(this), _msgSender(), assetAmount);

    if (usbAmount > 0) {
      uint256 usbBurnShares = IUSB(usbToken).burn(_msgSender(), usbAmount);
      _usbTotalShares = _usbTotalShares.sub(usbBurnShares);
    }

    if (leveragedTokenAmount > 0) {
      ILeveragedToken(leveragedToken).burn(_msgSender(), leveragedTokenAmount);
    }
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
    _currentVaultPhase = getVaultPhase();
    if (_lastCheckedVaultPhase == Constants.VaultPhase.Stability && _currentVaultPhase == Constants.VaultPhase.Stability) {
      // noop
    }
    else {
      (uint256 price, ) = IPriceFeed(assetTokenPriceFeed).latestPrice();
      _stableAssetPrice = price;
    }

    _;
    _lastCheckedVaultPhase = _currentVaultPhase;
  }

  modifier doSettleInterest() {
    // _settleInterest();
    _;
    // _startOrPauseInterestGeneration();
  }

  // TODO: delete
  modifier doCheckAAR() {
    _;
    _AAR(); // update _aarBelowSafeLineTime and _aarBelowCircuitBreakerLineTime
  }

  /* =============== EVENTS ============= */

  event UpdateParamValue(bytes32 indexed param, uint256 value);
  
  event USBMinted(address indexed user, uint256 assetTokenAmount, uint256 usbTokenAmount, uint256 usbSharesAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event LeveragedTokenMinted(address indexed user, uint256 assetTokenAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  // event AssetRedeemedWithUSB(address indexed user, uint256 usbTokenAmount, uint256 assetTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  // event AssetRedeemedWithUSBFeeCollected(address indexed user, address indexed feeTo, uint256 usbTokenAmount, uint256 feeAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithPairs(address indexed user, uint256 usbAmount, uint256 leveragedTokenAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithUSB(address indexed user, uint256 usbAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  event AssetRedeemedWithLeveragedToken(address indexed user, uint256 leveragedTokenAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  // event AssetRedeemedWithPairsFeeCollected(address indexed user, address indexed feeTo, uint256 xTokenAmount, uint256 fee, uint256 pairedUSBAmount, uint256 assetAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);
  // event UsbToLeveragedTokens(address indexed user, uint256 usbAmount, uint256 xTokenAmount, uint256 assetTokenPrice, uint256 assetTokenPriceDecimals);

  event InterestSettlement(uint256 interestAmount, bool distributed);
}