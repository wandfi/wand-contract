// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

library Constants {
  /**
   * @notice The address interpreted as native token of the chain.
   */
  address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  uint256 public constant PROTOCOL_DECIMALS = 10;

  struct Terms {
    uint256 T1;
    uint256 T2;
    uint256 T3;
    uint256 T4;
    uint256 T5;
    uint256 T6;
    uint256 T7;
    uint256 T8;
  }

  enum VaultPhase {
    Empty,
    Stability,
    AdjustmentBelowAARS,
    AdjustmentAboveAARU
  }

  struct VaultState {
    uint256 M_ETH;
    uint256 P_ETH_i;
    uint256 P_ETH;
    uint256 P_ETH_DECIMALS;
    uint256 M_USB_ETH;
    uint256 M_ETHx;
    uint256 aar;
    uint256 AART;
    uint256 AARS;
    uint256 AARU;
    uint256 AARC;
    uint256 AARDecimals;
    uint256 RateR;
    uint256 aarBelowSafeLineTime;
    uint256 settingsDecimals;

    uint256 aar_;
    uint256 r;
  }

  enum PtyPoolType {
    RedeemByUsbBelowAARS,
    MintUsbAboveAARU
  }
}