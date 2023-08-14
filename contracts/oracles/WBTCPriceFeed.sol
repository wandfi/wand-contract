// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IPriceFeed.sol";

/**
 * @dev Get WBTC price based on Chainlink 'WBTC / BTC' and 'BTC / USD' price feeds
 */
contract WBTCPriceFeed is IPriceFeed {
  using SafeCast for int256;
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

  function latestPrice() external view override returns (uint256, uint256) {
    (uint80 roundId1, int256 answer1, , uint256 updatedAt1, uint80 answeredInRound1) = wbtcToBTC.latestRoundData();
    (uint80 roundId2, int256 answer2, , uint256 updatedAt2, uint80 answeredInRound2) = btcToUSD.latestRoundData();

    require(answeredInRound1 >= roundId1 && answeredInRound2 >= roundId2, "answer is stale");
    require(updatedAt1 > 0 && updatedAt2 > 0, "round is incomplete");
    require(answer1 > 0 && answer2 > 0, "Invalid feed answer");

    uint256 price1 = answer1.toUint256();
    uint256 price2 = answer2.toUint256();
    uint256 price = price1.mul(price2).mul(10 ** _decimals).div(10 ** wbtcToBTC.decimals()).div(10 ** btcToUSD.decimals());
    return (price, Math.min(updatedAt1, updatedAt2));
  }
}