// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IVault {
  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() external view returns (uint256);

  function usbTotalShares() external view returns (uint256);

  function assetTotalAmount() external view returns (uint256);

  function assetToken() external view returns (address);

  function assetTokenPrice() external view returns (uint256, uint256);

  function leveragedToken() external view returns (address);

  function getParamValue(bytes32 param) external view returns (uint256);

  /**
   * @notice Current adequency ratio of the pool, with decimals specified via AARDecimals()
   */
  function AAR() external view returns (uint256);

  function AARDecimals() external view returns (uint256);

  function calcMintPairsAtStabilityPhase(uint256 assetAmount) external view returns (uint256, uint256);

  function calcMintPairsAtAdjustmentPhase(uint256 assetAmount) external view returns (uint256, uint256);

  function calcMintUsbAboveAARU(uint256 assetAmount) external view returns (uint256);

  function calcMintLeveragedTokensBelowAARS(uint256 assetAmount) external view returns (uint256);

  function calcPairdLeveragedTokenAmount(uint256 usbAmount) external view returns (uint256);
}