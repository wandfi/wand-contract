// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../tokens/Usb.sol";

contract MockUsb is Usb {
  constructor() Usb(address(0)) {}

  modifier onlyVault() override {
    _checkOwner();
    _;
  }
}