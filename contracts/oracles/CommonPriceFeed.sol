// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../interfaces/IPriceFeed.sol";

contract CommonPriceFeed is IPriceFeed {
  using SafeCast for int256;

  string internal asset;
  AggregatorV3Interface internal assetToUSD;

  constructor(string memory _asset, address _assetToUSD) {
    asset = _asset;
    assetToUSD = AggregatorV3Interface(_assetToUSD);
  }

  function decimals() external view override returns (uint8) {
    return assetToUSD.decimals();
  }

  function assetSymbol() external view override returns (string memory) {
    return asset;
  }

  function latestPrice() external view override returns (uint256, uint256) {
    (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = assetToUSD.latestRoundData();
    /*
      answeredInRound: The round ID in which the answer was computed
      updatedAt: Timestamp of when the round was updated
      answer: The answer for this round
    */
    require(answeredInRound >= roundId, "answer is stale");
    require(updatedAt > 0, "round is incomplete");
    require(answer > 0, "Invalid feed answer");
    return (answer.toUint256(), updatedAt);
  }
}