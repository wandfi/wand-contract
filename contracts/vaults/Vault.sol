// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";
import "../interfaces/IWandProtocol.sol";
import "../interfaces/ILeveragedToken.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IPtyPool.sol";
import "../interfaces/IUsb.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultCalculator.sol";

contract Vault is IVault, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  IWandProtocol public immutable wandProtocol;
  IProtocolSettings public immutable settings;
  IVaultCalculator public immutable vaultCalculator;
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

  Constants.VaultPhase internal _vaultPhase;

  uint256 internal _stableAssetPrice;

  uint256 internal _lastYieldsSettlementTime;

  uint256 internal _aarBelowSafeLineTime;
  uint256 internal _aarBelowCircuitBreakerLineTime;

  constructor(
    address _wandProtocol,
    address _vaultCalculator,
    address _assetToken_,
    address _assetTokenPriceFeed_,
    address _leveragedToken_,
    bytes32[] memory assetPoolParams, uint256[] memory assetPoolParamsValues
  )  {
    require(
      _wandProtocol != address(0) && _vaultCalculator != address(0) && _assetToken_ != address(0) && _assetTokenPriceFeed_ != address(0) && _leveragedToken_ != address(0), 
      "Zero address detected"
    );
    require(assetPoolParams.length == assetPoolParamsValues.length, "Invalid params length");

    wandProtocol = IWandProtocol(_wandProtocol);
    require(msg.sender == wandProtocol.vaultFactory(), "Vault should only be created by factory contract");

    vaultCalculator = IVaultCalculator(_vaultCalculator);
    _assetToken = _assetToken_;
    _assetTokenPriceFeed = _assetTokenPriceFeed_;
    _leveragedToken = _leveragedToken_;
    _usbToken = wandProtocol.usbToken();

    settings = IProtocolSettings(IWandProtocol(_wandProtocol).settings());
    _settingsDecimals = settings.decimals();

    for (uint256 i = 0; i < assetPoolParams.length; i++) {
      _updateParam(assetPoolParams[i], assetPoolParamsValues[i]);
    }

    _vaultPhase = Constants.VaultPhase.Empty;
  }

  /* ================= VIEWS ================ */

  function usbToken() public view returns (address) {
    return _usbToken;
  }

  function usbTotalSupply() public view returns (uint256) {
    return IUsb(_usbToken).getBalanceByShares(_usbTotalShares);
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

  function assetTokenPriceFeed() public view returns (address) {
    return _assetTokenPriceFeed;
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

  function vaultPhase() public view returns (Constants.VaultPhase) {
    return _vaultPhase;
  }

  function vaultState() public view returns (Constants.VaultState memory) {
    return _getVaultState();
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

  /* ========== Mint FUNCTIONS ========== */

  function mintPairsAtStabilityPhase(uint256 assetAmount) external payable nonReentrant noneZeroValue(assetAmount) onUserAction(true) {
    require(_vaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    (Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = vaultCalculator.calcMintPairsAtStabilityPhase(this, assetAmount);

    _doMint(assetAmount, S, usbOutAmount, leveragedTokenOutAmount);
  }

  function mintPairsAtAdjustmentPhase(uint256 assetAmount) external payable nonReentrant noneZeroValue(assetAmount) onUserAction(true) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || _vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment phase");

    (Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) = vaultCalculator.calcMintPairsAtAdjustmentPhase(this, assetAmount);
    _doMint(assetAmount, S, usbOutAmount, leveragedTokenOutAmount);
  }

  function mintUSBAboveAARU(uint256 assetAmount) external payable nonReentrant noneZeroValue(assetAmount) onUserAction(true) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    (Constants.VaultState memory S, uint256 usbOutAmount) = vaultCalculator.calcMintUsbAboveAARU(this, assetAmount);
    _doMint(assetAmount, S, usbOutAmount, 0);
  }

  function mintLeveragedTokensBelowAARS(uint256 assetAmount) external payable nonReentrant noneZeroValue(assetAmount) onUserAction(true) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    (Constants.VaultState memory S, uint256 leveragedTokenOutAmount) = vaultCalculator.calcMintLeveragedTokensBelowAARS(this, assetAmount);
    _doMint(assetAmount, S, 0, leveragedTokenOutAmount);
  }

   /* ========== Redeem FUNCTIONS ========== */

  function redeemByPairsWithExpectedUSBAmount(uint256 usbAmount) external payable nonReentrant noneZeroValue(usbAmount) onUserAction(true) {
    require(usbAmount <= IUsb(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    uint256 pairdLeveragedTokenAmount = vaultCalculator.calcPairdLeveragedTokenAmount(this, usbAmount);
    require(pairdLeveragedTokenAmount <= ILeveragedToken(_leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = vaultCalculator.calcPairedRedeemAssetAmount(this, pairdLeveragedTokenAmount);
    uint256 netRedeemAmount = _doRedeem(assetOutAmount, S, usbAmount, pairdLeveragedTokenAmount);

    emit AssetRedeemedWithPairs(_msgSender(), usbAmount, pairdLeveragedTokenAmount, netRedeemAmount, S.P_ETH, S.P_ETH_DECIMALS);
  }

  function redeemByPairsWithExpectedLeveragedTokenAmount(uint256 leveragedTokenAmount) external payable nonReentrant noneZeroValue(leveragedTokenAmount) onUserAction(true) {
    require(leveragedTokenAmount <= ILeveragedToken(_leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    uint256 pairedUSBAmount = vaultCalculator.calcPairedUsbAmount(this, leveragedTokenAmount);
    require(pairedUSBAmount <= IUsb(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = vaultCalculator.calcPairedRedeemAssetAmount(this, leveragedTokenAmount);
    uint256 netRedeemAmount = _doRedeem(assetOutAmount, S, pairedUSBAmount, leveragedTokenAmount);

    emit AssetRedeemedWithPairs(_msgSender(), pairedUSBAmount, leveragedTokenAmount, netRedeemAmount, S.P_ETH, S.P_ETH_DECIMALS);
  }

  function redeemByLeveragedTokenAboveAARU(uint256 leveragedTokenAmount) external payable nonReentrant noneZeroValue(leveragedTokenAmount) onUserAction(true) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");
    require(leveragedTokenAmount <= ILeveragedToken(_leveragedToken).balanceOf(_msgSender()), "Not enough leveraged token balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = vaultCalculator.calcRedeemByLeveragedTokenAboveAARU(this, leveragedTokenAmount);
    uint256 netRedeemAmount = _doRedeem(assetOutAmount, S, 0, leveragedTokenAmount);

    emit AssetRedeemedWithLeveragedToken(_msgSender(), leveragedTokenAmount, netRedeemAmount, S.P_ETH, S.P_ETH_DECIMALS);
  }

  function redeemByUsbBelowAARS(uint256 usbAmount) external payable nonReentrant noneZeroValue(usbAmount) onUserAction(true) {
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");
    require(usbAmount <= IUsb(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");

    (Constants.VaultState memory S, uint256 assetOutAmount) = vaultCalculator.calcRedeemByUsbBelowAARS(this, usbAmount);
    uint256 netRedeemAmount = _doRedeem(assetOutAmount, S, usbAmount, 0);

    emit AssetRedeemedWithUSB(_msgSender(), usbAmount, netRedeemAmount, S.P_ETH, S.P_ETH_DECIMALS);
  }

  /* ========== Other FUNCTIONS ========== */

  function usbToLeveragedTokens(uint256 usbAmount) external nonReentrant noneZeroValue(usbAmount) onUserAction(false) {  
    require(usbAmount <= IUsb(_usbToken).balanceOf(_msgSender()), "Not enough USB balance");
    require(_vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS || _vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment phase");

    (Constants.VaultState memory S, uint256 leveragedTokenAmount) = vaultCalculator.calcUsbToLeveragedTokens(this, usbAmount);
    
    uint256 usbSharesAmount = IUsb(_usbToken).burn(_msgSender(), usbAmount);
    _usbTotalShares = _usbTotalShares.sub(usbSharesAmount);
    emit UsbBurned(_msgSender(), usbAmount, usbSharesAmount, S.P_ETH, S.P_ETH_DECIMALS);

    ILeveragedToken(_leveragedToken).mint(_msgSender(), leveragedTokenAmount);
    emit LeveragedTokenMinted(_msgSender(), usbAmount, leveragedTokenAmount, S.P_ETH, S.P_ETH_DECIMALS);

    emit UsbToLeveragedTokens(_msgSender(), usbAmount, leveragedTokenAmount, S.P_ETH, S.P_ETH_DECIMALS);
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

  function _doMint(uint256 assetAmount, Constants.VaultState memory S, uint256 usbOutAmount, uint256 leveragedTokenOutAmount) internal {
    _assetTotalAmount = _assetTotalAmount.add(assetAmount);
    TokensTransfer.transferTokens(_assetToken, _msgSender(), address(this), assetAmount);

    if (usbOutAmount > 0) {
      uint256 usbSharesAmount = IUsb(_usbToken).mint(_msgSender(), usbOutAmount);
      _usbTotalShares = _usbTotalShares.add(usbSharesAmount);
      emit UsbMinted(_msgSender(), assetAmount, usbOutAmount, usbSharesAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }

    if (leveragedTokenOutAmount > 0) {
      ILeveragedToken(_leveragedToken).mint(_msgSender(), leveragedTokenOutAmount);
      emit LeveragedTokenMinted(_msgSender(), assetAmount, leveragedTokenOutAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }
  }

  function _doRedeem(uint256 assetAmount, Constants.VaultState memory S, uint256 usbAmount, uint256 leveragedTokenAmount) internal returns (uint256) {
    require(assetAmount <= _assetTotalAmount, "Not enough asset balance");

    _assetTotalAmount = _assetTotalAmount.sub(assetAmount);

    uint256 totalFees = assetAmount.mul(_vaultParamValue("C")).div(10 ** S.settingsDecimals);
    uint256 feesToTreasury = totalFees.mul(_vaultParamValue("TreasuryFeeRate")).div(10 ** S.settingsDecimals);
    uint256 feesToPtyPoolBelowAARS = totalFees.sub(feesToTreasury).div(2);
    uint256 feesToPtyPoolAboveAARU = totalFees.sub(feesToTreasury).sub(feesToPtyPoolBelowAARS);

    uint256 netRedeemAmount = assetAmount.sub(totalFees);
    TokensTransfer.transferTokens(_assetToken, address(this), _msgSender(), netRedeemAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), settings.treasury(), feesToTreasury);

    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolBelowAARS), feesToPtyPoolBelowAARS);
    ptyPoolBelowAARS.addMatchingYields(feesToPtyPoolBelowAARS);

    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolAboveAARU), feesToPtyPoolAboveAARU);
    ptyPoolAboveAARU.addStakingYields(feesToPtyPoolAboveAARU);

    if (usbAmount > 0) {
      uint256 usbBurnShares = IUsb(_usbToken).burn(_msgSender(), usbAmount);
      _usbTotalShares = _usbTotalShares.sub(usbBurnShares);
      emit UsbBurned(_msgSender(), usbAmount, usbBurnShares, S.P_ETH, S.P_ETH_DECIMALS);
    }

    if (leveragedTokenAmount > 0) {
      ILeveragedToken(_leveragedToken).burn(_msgSender(), leveragedTokenAmount);
      emit LeveragedTokenBurned(_msgSender(), leveragedTokenAmount, S.P_ETH, S.P_ETH_DECIMALS);
    }

    return netRedeemAmount;
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

    uint256 deltaAssetAmount = deltaUsbAmount.mul(10 ** S.P_ETH_DECIMALS).div(S.P_ETH);
    _assetTotalAmount = _assetTotalAmount.sub(deltaAssetAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolBelowAARS), deltaAssetAmount);

    uint256 usbBurnShares = IUsb(_usbToken).burn(address(ptyPoolBelowAARS), deltaUsbAmount);
    _usbTotalShares = _usbTotalShares.sub(usbBurnShares);
    emit UsbBurned(address(ptyPoolBelowAARS), deltaUsbAmount, usbBurnShares, S.P_ETH, S.P_ETH_DECIMALS);

    ptyPoolBelowAARS.notifyMatchedBelowAARS(deltaAssetAmount);
  }

  function _ptyPoolMatchAboveAARU() internal {
    Constants.VaultState memory S = _getVaultState();

    // ΔETH = (Musb-eth * AART - M_ETH * P_ETH) / (P_ETH * (AART - 1))
    uint256 deltaAssetAmount = S.M_USB_ETH.mul(S.AART).mul(10 ** S.P_ETH_DECIMALS).sub(
      S.M_ETH.mul(S.P_ETH)
    ).div(
      S.P_ETH.mul(S.AART.sub(10 ** S.AARDecimals))
    ).div(10 ** S.P_ETH_DECIMALS).div(10 ** S.AARDecimals);

    uint256 minAssetAmount = _vaultParamValue("PtyPoolMinAssetAmount");
    uint256 ptyPoolAssetBalance = ptyPoolAboveAARU.totalStakingBalance();
    if (deltaAssetAmount >= ptyPoolAssetBalance || deltaAssetAmount + minAssetAmount >= ptyPoolAssetBalance) {
      deltaAssetAmount = ptyPoolAssetBalance;
    }

    uint256 deltaUsbAmount = deltaAssetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    uint256 usbSharesAmount = IUsb(_usbToken).mint(address(ptyPoolAboveAARU), deltaUsbAmount);
    _usbTotalShares = _usbTotalShares.add(usbSharesAmount);
    emit UsbMinted(_msgSender(), deltaAssetAmount, deltaUsbAmount, usbSharesAmount, S.P_ETH, S.P_ETH_DECIMALS);

    ptyPoolAboveAARU.notifyMatchedAboveAARU(deltaAssetAmount, usbSharesAmount);
  }

  function _doSettleYields() internal {
    uint256 timeElapsed = block.timestamp.sub(_lastYieldsSettlementTime);
    uint256 Y = _vaultParamValue("Y");
    uint256 deltaAssetAmount = timeElapsed.mul(Y).mul(_assetTotalAmount).div(365 days).div(10 ** _settingsDecimals);
    if (deltaAssetAmount == 0) {
      return;
    }

    Constants.VaultState memory S;
    uint256 usbOutAmount = 0;
    uint256 leveragedTokenOutAmount = 0;
    if(_vaultPhase == Constants.VaultPhase.Stability) {
      (S, usbOutAmount, leveragedTokenOutAmount) = vaultCalculator.calcMintPairsAtStabilityPhase(this, deltaAssetAmount);
    }
    else if(_vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || _vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS) {
      (, usbOutAmount, leveragedTokenOutAmount) = vaultCalculator.calcMintPairsAtAdjustmentPhase(this, deltaAssetAmount);
    }

    if (usbOutAmount > 0) {
      IUsb(_usbToken).rebase(usbOutAmount);
    }

    if (leveragedTokenOutAmount > 0) {
      ILeveragedToken(_leveragedToken).mint(_msgSender(), leveragedTokenOutAmount);
      uint256 toPtyPoolBelowAARS = leveragedTokenOutAmount.div(2);
      TokensTransfer.transferTokens(_leveragedToken, address(this), address(ptyPoolBelowAARS), toPtyPoolBelowAARS);
      ptyPoolBelowAARS.addStakingYields(toPtyPoolBelowAARS);

      uint256 toPtyPoolAboveAARU = leveragedTokenOutAmount.sub(toPtyPoolBelowAARS);
      TokensTransfer.transferTokens(_leveragedToken, address(this), address(ptyPoolAboveAARU), toPtyPoolAboveAARU);
      ptyPoolAboveAARU.addMatchingYields(toPtyPoolAboveAARU);
    }

    emit YieldsSettlement(usbOutAmount, leveragedTokenOutAmount);
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

  modifier onUserAction(bool settleYields) {
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

    if (settleYields) {
      if (_lastYieldsSettlementTime != 0) {
        _doSettleYields();
      }
      _lastYieldsSettlementTime = block.timestamp;
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

  event YieldsSettlement(uint256 usbYieldsAmount, uint256 leveragedTokenYieldsAmount);
}