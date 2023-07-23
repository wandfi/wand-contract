// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAssetPool.sol";
import "../libs/Constants.sol";

interface IAssetPoolCalculator {

  function AAR(IAssetPool assetPool) external pure returns (uint256);

  function pairedUSBAmountToRedeemByXTokens(IAssetPool assetPool, uint256 xTokenAmount) external pure returns (uint256);

  function calculateUSBToXTokensOut(Constants.AssetPoolState memory S, address account, uint256 usbAmount) external pure returns (uint256);

  function calculateMintUSBOut(Constants.AssetPoolState memory S, uint256 assetAmount) external pure returns (uint256);

  function calculateMintXTokensOut(IAssetPool assetPool, uint256 assetAmount, uint256 msgValue) external pure returns (uint256);

}