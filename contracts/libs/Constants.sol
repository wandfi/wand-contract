// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

library Constants {
  /**
   * @notice The address interpreted as native token of the chain.
   */
  address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  uint256 public constant PROTOCOL_DECIMALS = 10;

  struct AssetPoolState {
    uint256 M_ETH;
    uint256 P_ETH;
    uint256 P_ETH_DECIMALS;
    uint256 M_USB_ETH;
    uint256 M_ETHx;
    uint256 aar;
    uint256 AART;
    uint256 AARS;
    uint256 AARC;
    uint256 AARDecimals;
    uint256 RateR;
    uint256 BasisR;
    uint256 BasisR2;
    uint256 aarBelowSafeLineTime;
    uint256 settingsDecimals;

    // uint256 Delta_USB;
    uint256 aar_;
    uint256 r;
  }

  enum InterestPoolStakingTokenType {
    Usb,
    UniswapV2PairLp,
    CurvePlainPoolLp
  }

  struct InterestPoolStakingTokenInfo {
    address stakingToken;
    InterestPoolStakingTokenType stakingTokenType;
    // Needed if staking token is Uniswap V2 or Curve PlainPool LP token
    address swapPool;
    uint256 swapPoolCoinsCount;
  }
}