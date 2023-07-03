// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IWandPool {

  // /**
  //  * @notice Returns the address of the asset token.
  //  */
  // function assetToken() external view returns (address);

  // /**
  //  * @notice Returns the address of the xToken.
  //  */
  // function assetXToken() external view returns (address);

  // /**
  //  * @notice Returns the address of the asset token price feed.
  //  */
  // function assetTokenPriceFeed() external view returns (address);

  function mint(uint256 amount) external payable;
}