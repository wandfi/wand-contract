// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

library Constants {
  /**
   * @notice The address interpreted as native token of the chain.
   */
  address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  uint256 public constant PROTOCOL_DECIMALS = 10;

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