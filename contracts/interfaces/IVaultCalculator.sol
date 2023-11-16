// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVault.sol";
import "../libs/Constants.sol";

interface IVaultCalculator {

  function AAR(IVault assetPool) external pure returns (uint256);

  function r(Constants.VaultState memory S) external view returns (uint256);

  function calculatePairedUSBAmountToRedeemByLeveragedTokens(IVault assetPool, uint256 xTokenAmount) external pure returns (uint256);

  function calculateUSBToLeveragedTokensOut(Constants.VaultState memory S, uint256 usbAmount) external pure returns (uint256);

  function calculateMintUSBOut(Constants.VaultState memory S, uint256 assetAmount) external pure returns (uint256);

  function calculateMintLeveragedTokensOut(IVault assetPool, uint256 assetAmount) external pure returns (uint256);

}