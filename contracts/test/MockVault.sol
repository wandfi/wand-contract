// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../interfaces/IPtyPool.sol";
import "../interfaces/IVault.sol";
import "../libs/Constants.sol";

contract MockVault is IVault {
  address internal immutable _assetToken;
  address internal immutable _usbToken;
  Constants.VaultPhase internal _vaultPhase;

  IPtyPool public ptyPoolBelowAARS;
  IPtyPool public ptyPoolAboveAARU;

  constructor(
    address _assetToken_,
    address _usbToken_
  ) {
    _assetToken = _assetToken_;
    _usbToken = _usbToken_;
    _vaultPhase = Constants.VaultPhase.Empty;
  }

  /* ========== IVault Functions ========== */

  function usbToken() external view override returns (address) {
    return _usbToken;
  }

  function assetToken() external view override returns (address) {
    return _assetToken;
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

  /* ========== Test Functions ========== */

  function testSetVaultPhase(Constants.VaultPhase _vaultPhase_) external {
    _vaultPhase = _vaultPhase_;
  }

}