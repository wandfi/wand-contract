// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IAssetPool {

  /**
   * @notice Total amount of $USB tokens minted (burned subtracted) by this pool
   */
  function usbTotalSupply() external view returns (uint256);

  function getAssetTotalAmount() external view returns (uint256);

  function getAssetTokenPrice() external view returns (uint256, uint256);

  function xToken() external view returns (address);

  /**
   * @notice Current adequency ratio of the pool, with decimals specified via AARDecimals()
   */
  function AAR() external view returns (uint256);

  function AARDecimals() external view returns (uint256);

  // function C1() external view returns (uint256);

  // function C2() external view returns (uint256);

  // function Y() external view returns (uint256);

  // function AART() external view returns (uint256);

  // function AARS() external view returns (uint256);

  // function AARC() external view returns (uint256);

  // function BasisR() external view returns (uint256);

  // function RateR() external view returns (uint256);

  // function BasisR2() external view returns (uint256);

  // function CiruitBreakPeriod() external view returns (uint256);

  // function settingsDecimals() external view returns (uint256);

  // function aarBelowSafeLineTime() external view returns (uint256);

  // function setC1(uint256 newC1) external;

  // function setC2(uint256 newC2) external;

  // function setY(uint256 newY) external;

  // function setBasisR(uint256 newBasisR) external;

  // function setRateR(uint256 newRateR) external;

  // function setBasisR2(uint256 newBasisR2) external;

  // function setCiruitBreakPeriod(uint256 newCiruitBreakPeriod) external;

  function calculateMintUSBOut(uint256 assetAmount) external view returns (uint256);
  
  function mintUSB(uint256 assetAmount) external payable;

  function calculateMintXTokensOut(uint256 assetAmount) external view returns (uint256);

  function mintXTokens(uint256 assetAmount) external payable;

  function redeemByUSB(uint256 usbAmount) external;

  function redeemByXTokens(uint256 xTokenAmount) external;

  function pairedUSBAmountToRedeemByXTokens(uint256 xTokenAmount) external view returns (uint256);

  function calculateUSBToXTokensOut(address account, uint256 usbAmount) external returns (uint256);

  function usbToXTokens(uint256 usbAmount) external;

  function calculateInterest() external view returns (uint256, uint256);

  function checkAAR() external; 

  function settleInterest() external;
}