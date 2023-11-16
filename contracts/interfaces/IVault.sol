// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IVault {

  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() external view returns (uint256);

  function getAssetTotalAmount() external view returns (uint256);

  function getAssetToken() external view returns (address);

  function getAssetTokenPrice() external view returns (uint256, uint256);

  function leveragedToken() external view returns (address);

  /**
   * @notice Current adequency ratio of the pool, with decimals specified via AARDecimals()
   */
  function AAR() external view returns (uint256);

  function AARDecimals() external view returns (uint256);

  function calculateMintUSBOut(uint256 assetAmount) external view returns (uint256);
  
  function calculateMintLeveragedTokensOut(uint256 assetAmount) external view returns (uint256);

  function calculatePairedUSBAmountToRedeemByLeveragedTokens(uint256 xTokenAmount) external view returns (uint256);

  function calculateUSBToLeveragedTokensOut(uint256 usbAmount) external returns (uint256);

  function calculateInterest() external view returns (uint256, uint256);
}