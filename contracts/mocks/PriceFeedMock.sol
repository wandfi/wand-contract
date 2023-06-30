// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "../interfaces/IPriceFeed.sol";

contract PriceFeedMock is IPriceFeed {

  bytes32 internal asset;
  uint8 internal priceDecimals;

  uint256 internal mockedPrice;

  constructor(bytes32 _asset, uint8 _priceDecimals) {
    asset = _asset;
    priceDecimals = _priceDecimals;
  }

  function decimals() external view override returns (uint8) {
    return priceDecimals;
  }

  function assetSymbol() external view override returns (bytes32) {
    return asset;
  }

  function latestPrice() external view override returns (uint256) {
    return mockedPrice;
  }

  function mockPrice(uint256 _mockPrice) external {
    mockedPrice = _mockPrice;
  }
}