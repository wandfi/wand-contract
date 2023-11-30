// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Constants.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IPtyPool.sol";
import "../interfaces/IVault.sol";

contract VaultCalculator {
  using SafeMath for uint256;

  /**
   * @dev AAReth = (M_ETH * P_ETH / Musb-eth) * 100%
   */
  function AAR(IVault vault) public view returns (uint256) {
    uint256 assetTotalAmount = vault.assetTotalAmount();
    if (assetTotalAmount == 0) {
      return 0;
    }
    if (vault.usbTotalSupply() == 0) {
      return type(uint256).max;
    }
    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = vault.assetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** vault.AARDecimals()).div(vault.usbTotalSupply());
  }

  function getVaultState(IVault vault, uint256 stableAssetPrice, uint256 settingsDecimals) public view returns (Constants.VaultState memory) {
    Constants.VaultState memory S;
    S.P_ETH_i = stableAssetPrice;
    S.M_ETH = vault.assetTotalAmount();
    (S.P_ETH, S.P_ETH_DECIMALS) = vault.assetTokenPrice();
    S.M_USB_ETH = vault.usbTotalSupply();
    S.M_ETHx = IERC20(vault.leveragedToken()).totalSupply();
    S.aar = AAR(vault);
    S.AART = vault.getParamValue("AART");
    S.AARS = vault.getParamValue("AARS");
    S.AARU = vault.getParamValue("AARU");
    S.AARC = vault.getParamValue("AARC");
    S.AARDecimals = vault.AARDecimals();
    S.RateR = vault.getParamValue("RateR");
    S.AARBelowSafeLineTime = vault.AARBelowSafeLineTime();
    S.AARBelowCircuitBreakerLineTime = vault.AARBelowCircuitBreakerLineTime();
    S.settingsDecimals = settingsDecimals;

    return S;
  }

  function calcMintPairsAtStabilityPhase(IVault vault, uint256 assetAmount) public view returns (Constants.VaultState memory, uint256, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.Empty || vaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    Constants.VaultState memory S = vault.vaultState();
    if (vaultPhase == Constants.VaultPhase.Empty) {
      (S.P_ETH_i, ) = IPriceFeed(vault.assetTokenPriceFeed()).latestPrice();
    }

    // ΔUSB = ΔETH * P_ETH_i * 1 / AART_eth
    // ΔETHx = ΔETH * (1 - 1 / AART_eth) = ΔETH * (AART_eth - 1) / AART_eth
    uint256 usbOutAmount = assetAmount.mul(S.P_ETH_i).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AART);
    uint256 leveragedTokenOutAmount = assetAmount.mul(
      (S.AART).sub(10 ** S.AARDecimals)
    ).div(S.AART);

    return (S, usbOutAmount, leveragedTokenOutAmount);
  }

  function calcMintPairsAtAdjustmentPhase(IVault vault, uint256 assetAmount) public view returns (Constants.VaultState memory, uint256, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU || vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment phase");

    Constants.VaultState memory S = vault.vaultState();

    // ΔUSB = ΔETH * P_ETH * 1 / AAR
    // ΔETHx = ΔETH * P_ETH * M_ETHx / (AAR * Musb-eth)
    Constants.Terms memory T;
    T.T1 = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    uint256 usbOutAmount = T.T1.mul(10 ** S.AARDecimals).div(S.aar);
    uint256 leveragedTokenOutAmount = T.T1
      .mul(S.M_ETHx).mul(10 ** S.AARDecimals).div(S.aar).div(S.M_USB_ETH);
    return (S, usbOutAmount, leveragedTokenOutAmount);
  }

  function calcMintUsbAboveAARU(IVault vault, uint256 assetAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    Constants.VaultState memory S = vault.vaultState();

    // ΔUSB = ΔETH * P_ETH
    uint256 usbOutAmount = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    return (S, usbOutAmount);
  }

  function calcMintLeveragedTokensBelowAARS(IVault vault, uint256 assetAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    Constants.VaultState memory S = vault.vaultState();

    // ΔETHx = ΔETH * P_ETH * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    uint256 leveragedTokenOutAmount = assetAmount.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(S.M_ETHx).div(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    );
    return (S, leveragedTokenOutAmount);
  }

  function calcPairdLeveragedTokenAmount(IVault vault, uint256 usbAmount) public view returns (uint256) {
    Constants.VaultState memory S = vault.vaultState();

    // ΔUSB = ΔETHx * Musb-eth / M_ETHx
    // ΔETHx = ΔUSB * M_ETHx / Musb-eth
    uint256 leveragedTokenOutAmount = usbAmount.mul(S.M_ETHx).div(S.M_USB_ETH);
    return leveragedTokenOutAmount;
  }

  function calcPairedUsbAmount(IVault vault, uint256 leveragedTokenAmount) public view returns (uint256) {
    Constants.VaultState memory S = vault.vaultState();

    // ΔUSB = ΔETHx * Musb-eth / M_ETHx
    // ΔETHx = ΔUSB * M_ETHx / Musb-eth
    uint256 usbOutAmount = leveragedTokenAmount.mul(S.M_USB_ETH).div(S.M_ETHx);
    return usbOutAmount;
  }

  function calcPairedRedeemAssetAmount(IVault vault, uint256 leveragedTokenAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = vault.vaultState();

    // ΔETH = ΔETHx * M_ETH / M_ETHx
    uint256 assetOutAmount = leveragedTokenAmount.mul(S.M_ETH).div(S.M_ETHx);
    return (S, assetOutAmount);
  }

  function calcRedeemByLeveragedTokenAboveAARU(IVault vault, uint256 leveragedTokenAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment above AARU phase");

    Constants.VaultState memory S = vault.vaultState();

    // ΔETH = ΔETHx * (M_ETH * P_ETH - Musb-eth) / (M_ETHx * P_ETH)
    uint256 assetOutAmount = leveragedTokenAmount.mul(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    ).div(S.M_ETHx.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS));
    return (S, assetOutAmount);
  }

  function calcRedeemByUsbBelowAARS(IVault vault, uint256 usbAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS, "Vault not at adjustment below AARS phase");

    Constants.VaultState memory S = vault.vaultState();

    if (S.aar < (10 ** S.AARDecimals)) {
      // ΔETH = ΔUSB * M_ETH / Musb-eth
      uint256 assetOutAmount = usbAmount.mul(S.M_ETH).div(S.M_USB_ETH);
      return (S, assetOutAmount);
    }
    else {
      // ΔETH = ΔUSB / P_ETH
      uint256 assetOutAmount = usbAmount.mul(10 ** S.P_ETH_DECIMALS).div(S.P_ETH);
      return (S, assetOutAmount);
    }
  }

  function calcUsbToLeveragedTokens(IVault vault, uint256 usbAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS || vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment phase");

    Constants.VaultState memory S = vault.vaultState();
    require(S.aar >= S.AARC || (block.timestamp.sub(S.AARBelowCircuitBreakerLineTime) >= vault.getParamValue("CircuitBreakPeriod")), "Conditional Discount Purchase suspended");

    // ΔETHx = ΔUSB * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth)
    uint256 leveragedTokenOutAmount = usbAmount.mul(S.M_ETHx).mul((10 ** S.settingsDecimals).add(_r(S))).div(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    ).div(10 ** S.settingsDecimals);
    return (S, leveragedTokenOutAmount);
  }

  // 𝑟 = vault.RateR() × 𝑡(h𝑟𝑠), since aar drop below 1.3;
  // r = 0 since aar above 2;
  function _r(Constants.VaultState memory S) internal view returns (uint256) {
    if (S.AARBelowSafeLineTime == 0) {
      return 0;
    }
    return S.RateR.mul(block.timestamp.sub(S.AARBelowSafeLineTime)).div(1 hours);
  }

  function calcDeltaUsbForPtyPoolMatchBelowAARS(IVault vault, address ptyPoolBelowAARS) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = vault.vaultState();

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

    uint256 minUsbAmount = vault.getParamValue("PtyPoolMinUsbAmount");
    uint256 ptyPoolUsbBalance = IERC20(vault.usbToken()).balanceOf(ptyPoolBelowAARS);
    if (ptyPoolUsbBalance <= minUsbAmount) {
      return (S, 0);
    }
    deltaUsbAmount = deltaUsbAmount > ptyPoolUsbBalance.sub(minUsbAmount) ? ptyPoolUsbBalance.sub(minUsbAmount) : deltaUsbAmount;
    return (S, deltaUsbAmount);
  }

  function calcDeltaAssetForPtyPoolMatchAboveAARU(IVault vault, address ptyPoolAboveAARU) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultState memory S = vault.vaultState();

    // ΔETH = (Musb-eth * AART - M_ETH * P_ETH) / (P_ETH * (AART - 1))
    uint256 deltaAssetAmount = S.M_USB_ETH.mul(S.AART).mul(10 ** S.P_ETH_DECIMALS).sub(
      S.M_ETH.mul(S.P_ETH)
    ).div(
      S.P_ETH.mul(S.AART.sub(10 ** S.AARDecimals))
    ).div(10 ** S.P_ETH_DECIMALS).div(10 ** S.AARDecimals);

    uint256 minAssetAmount = vault.getParamValue("PtyPoolMinAssetAmount");
    uint256 ptyPoolAssetBalance = IPtyPool(ptyPoolAboveAARU).totalStakingBalance();
    if (deltaAssetAmount >= ptyPoolAssetBalance || deltaAssetAmount + minAssetAmount >= ptyPoolAssetBalance) {
      deltaAssetAmount = ptyPoolAssetBalance;
    }

    return (S, deltaAssetAmount);
  }

}