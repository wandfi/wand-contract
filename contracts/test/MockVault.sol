// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../interfaces/ILeveragedToken.sol";
import "../interfaces/IPtyPool.sol";
import "../interfaces/IUsb.sol";
import "../interfaces/IVault.sol";
import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";

contract MockVault is IVault {
  address internal immutable _assetToken;
  address internal immutable _usbToken;
  address internal immutable _leveragedToken;

  Constants.VaultPhase internal _vaultPhase;

  IPtyPool public ptyPoolBelowAARS;
  IPtyPool public ptyPoolAboveAARU;

  constructor(
    address _assetToken_,
    address _usbToken_,
    address _leveragedToken_
  ) {
    _assetToken = _assetToken_;
    _usbToken = _usbToken_;
    _leveragedToken = _leveragedToken_;
    _vaultPhase = Constants.VaultPhase.Empty;
  }

  receive() external payable {}

  /* ========== IVault Functions ========== */

  function AARDecimals() external pure returns (uint256) {
    return 0;
  }

  function usbToken() external view override returns (address) {
    return _usbToken;
  }

  function assetToken() external view override returns (address) {
    return _assetToken;
  }

  function assetTokenDecimals() public pure returns (uint8) {
    return 18;
  }

  function assetTokenPriceFeed() public pure returns (address) {
    return address(0);
  }

  function assetTotalAmount() external pure returns (uint256) {
    return 0;
  }

  function assetTokenPrice() external pure returns (uint256, uint256) {
    return (0, 0);
  }

  function leveragedToken() external view returns (address) {
    return _leveragedToken;
  }

  function usbTotalSupply() external pure returns (uint256) {
    return 0;
  }

  function getParamValue(bytes32) external pure returns (uint256) {
    return 0;
  }

  function vaultPhase() external view override returns (Constants.VaultPhase) {
    return _vaultPhase;
  }

  function vaultState() external pure override returns (Constants.VaultState memory) {
    Constants.VaultState memory S;
    return S;
  }

  function setPtyPools(address _ptyPoolBelowAARS, address _ptyPoolAboveAARU) external {
    ptyPoolBelowAARS = IPtyPool(_ptyPoolBelowAARS);
    ptyPoolAboveAARU = IPtyPool(_ptyPoolAboveAARU);
  }

  function AARBelowSafeLineTime() public pure returns (uint256) {
    return 0;
  }

  function AARBelowCircuitBreakerLineTime() public pure returns (uint256) {
    return 0;
  }

  /* ========== Mock Functions ========== */

  function mockSetVaultPhase(Constants.VaultPhase _vaultPhase_) external {
    _vaultPhase = _vaultPhase_;
  }

  function mockAddStakingYieldsToPtyPoolBelowAARS(uint256 leveragedTokenAmount) external {
    ILeveragedToken(_leveragedToken).mint(address(this), leveragedTokenAmount);
    TokensTransfer.transferTokens(_leveragedToken, address(this), address(ptyPoolBelowAARS), leveragedTokenAmount);
    ptyPoolBelowAARS.addStakingYields(leveragedTokenAmount);
  }

  function mockAddMatchingYieldsToPtyPoolBelowAARS(uint256 assetAmount) payable external {
    TokensTransfer.transferTokens(_assetToken, msg.sender, address(this), assetAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolBelowAARS), assetAmount);
    ptyPoolBelowAARS.addMatchingYields(assetAmount);
  }

  function mockMatchedPtyPoolBelowAARS(uint256 deltaAssetAmount, uint256 deltaUsbAmount) payable external {
    TokensTransfer.transferTokens(_assetToken, msg.sender, address(this), deltaAssetAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolBelowAARS), deltaAssetAmount);

    IUsb(_usbToken).burn(address(ptyPoolBelowAARS), deltaUsbAmount);
    ptyPoolBelowAARS.notifyMatchedBelowAARS(deltaAssetAmount);
  }

  function mockAddStakingYieldsToPtyPoolAboveAARU(uint256 assetAmount) payable external {
    TokensTransfer.transferTokens(_assetToken, msg.sender, address(this), assetAmount);
    TokensTransfer.transferTokens(_assetToken, address(this), address(ptyPoolAboveAARU), assetAmount);
    ptyPoolAboveAARU.addStakingYields(assetAmount);
  }

  function mockAddMatchingYieldsToPtyPoolAboveAARU(uint256 leveragedTokenAmount) external {
    ILeveragedToken(_leveragedToken).mint(address(this), leveragedTokenAmount);
    TokensTransfer.transferTokens(_leveragedToken, address(this), address(ptyPoolAboveAARU), leveragedTokenAmount);
    ptyPoolAboveAARU.addMatchingYields(leveragedTokenAmount);
  }

  function mockMatchedPtyPoolAboveAARU(uint256 deltaAssetAmount, uint256 deltaUsbAmount) external {
    uint256 usbSharesAmount = IUsb(_usbToken).mint(address(ptyPoolAboveAARU), deltaUsbAmount);
    ptyPoolAboveAARU.notifyMatchedAboveAARU(deltaAssetAmount, usbSharesAmount);
  }


}