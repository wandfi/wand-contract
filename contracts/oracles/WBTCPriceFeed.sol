// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IPriceFeed.sol";

/**
 * @dev Get WBTC price based on Chainlink 'WBTC / BTC' and 'BTC / USD' price feeds
 */
contract WBTCPriceFeed is IPriceFeed {
  using SafeMath for uint256;

  uint8 internal constant _decimals = 8;

  AggregatorV3Interface internal wbtcToBTC;
  AggregatorV3Interface internal btcToUSD;

  constructor(address _wbtcToBTC, address _btcToUSD) {
    wbtcToBTC = AggregatorV3Interface(_wbtcToBTC);
    btcToUSD = AggregatorV3Interface(_btcToUSD);
  }

  function decimals() external pure override returns (uint8) {
    return _decimals;
  }

  function assetSymbol() external pure override returns (string memory) {
    return "WBTC";
  }

  function latestPrice() external view override returns (uint256) {
    (, int256 price1, , , ) = wbtcToBTC.latestRoundData();
    (, int256 price2, , , ) = btcToUSD.latestRoundData();
    require(price1 >= 0 && price2 >= 0, "WBTCPriceFeed: negative price");

    return uint256(price1).mul(uint256(price2)).mul(10 ** _decimals).div(10 ** wbtcToBTC.decimals()).div(10 ** btcToUSD.decimals());
  }
}