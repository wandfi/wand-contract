// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../libs/Constants.sol";
import "./IVault.sol";

interface IVaultCalculator {

  function calcMintPairsAtStabilityPhase(IVault vault, uint256 assetAmount) external view returns (Constants.VaultState memory, uint256, uint256);

  function calcMintPairsAtAdjustmentPhase(IVault vault, uint256 assetAmount) external view returns (Constants.VaultState memory, uint256, uint256);

  function calcMintUsbAboveAARU(IVault vault, uint256 assetAmount) external  view returns (Constants.VaultState memory, uint256);

  function calcMintLeveragedTokensBelowAARS(IVault vault, uint256 assetAmount) external view returns (Constants.VaultState memory, uint256);

  function calcPairdLeveragedTokenAmount(IVault vault, uint256 usbAmount) external view returns (uint256);

  function calcPairedUsbAmount(IVault vault, uint256 leveragedTokenAmount) external view returns (uint256);

  function calcPairedRedeemAssetAmount(IVault vault, uint256 leveragedTokenAmount) external view returns (Constants.VaultState memory, uint256);

  function calcRedeemByLeveragedTokenAboveAARU(IVault vault, uint256 leveragedTokenAmount) external view returns (Constants.VaultState memory, uint256);

  function calcRedeemByUsbBelowAARS(IVault vault, uint256 usbAmount) external view returns (Constants.VaultState memory, uint256);

  function calcUsbToLeveragedTokens(IVault vault, uint256 usbAmount) external view returns (Constants.VaultState memory, uint256);
}