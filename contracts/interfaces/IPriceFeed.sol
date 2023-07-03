// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IPriceFeed {
  /**
   * @notice The number of decimals in the returned price
   */
  function decimals() external view returns (uint8);

  /**
   * @notice The symbol of the underlying asset, like 'ETH', 'BTC', 'WBTC', etc.
   */
  function assetSymbol() external view returns (bytes32);

  /**
   * @notice Returns the latest price of the asset in USD
   */
  function latestPrice() external view returns (uint256);
}