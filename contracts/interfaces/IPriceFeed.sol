// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IPriceFeed {
  /**
   * @dev The number of decimals in the returned price
   */
  function decimals() external view returns (uint8);

  /**
   * @dev The symbol of the underlying asset, like 'ETH', 'BTC', 'WBTC', etc.
   */
  function assetSymbol() external view returns (bytes32);

  /**
   * @dev Returns the latest price of the asset in USD
   */
  function latestPrice() external view returns (uint256);
}