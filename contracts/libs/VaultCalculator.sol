// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Constants.sol";
import "../interfaces/IVault.sol";

contract VaultCalculator {
  using SafeMath for uint256;

  function calcMintPairsAtStabilityPhase(IVault vault, uint256 assetAmount) public view returns (Constants.VaultState memory, uint256, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.Empty || vaultPhase == Constants.VaultPhase.Stability, "Vault not at stable phase");

    Constants.VaultState memory S = vault.vaultState();

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

  function calcUsbToLeveragedTokens(IVault vault, uint256 usbAmount) public view returns (Constants.VaultState memory, uint256) {
    Constants.VaultPhase vaultPhase = vault.vaultPhase();
    require(vaultPhase == Constants.VaultPhase.AdjustmentBelowAARS || vaultPhase == Constants.VaultPhase.AdjustmentAboveAARU, "Vault not at adjustment phase");

    Constants.VaultState memory S = vault.vaultState();

    // ΔETHx = ΔUSB * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth)
    uint256 leveragedTokenOutAmount = usbAmount.mul(S.M_ETHx).mul((10 ** S.settingsDecimals).add(_r(S))).div(
      S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
    );
    return (S, leveragedTokenOutAmount);
  }

  // 𝑟 = vault.RateR() × 𝑡(h𝑟𝑠), since aar drop below 1.3;
  // r = 0 since aar above 2;
  function _r(Constants.VaultState memory S) internal view returns (uint256) {
    if (S.aarBelowSafeLineTime == 0) {
      return 0;
    }
    return S.RateR.mul(block.timestamp.sub(S.aarBelowSafeLineTime)).div(1 hours);
  }

}