// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPriceFeed.sol";

contract CommonPriceFeed is IPriceFeed {

  bytes32 internal asset;
  AggregatorV3Interface internal assetToUSD;

  constructor(bytes32 _asset, address _assetToUSD) {
    asset = _asset;
    assetToUSD = AggregatorV3Interface(_assetToUSD);
  }

  function decimals() external view override returns (uint8) {
    return assetToUSD.decimals();
  }

  function assetSymbol() external view override returns (bytes32) {
    return asset;
  }

  function latestPrice() external view override returns (uint256) {
    // Chainlink Data Feeds use int instead of uint because some prices can be negative, like when oil futures dropped below 0.
    // But in our case, prices should always be positive, so we can safely cast to uint.
    (, int256 price, , , ) = assetToUSD.latestRoundData();
    require(price >= 0, "CommonPriceFeed: negative price");
    return uint256(price);
  }
}