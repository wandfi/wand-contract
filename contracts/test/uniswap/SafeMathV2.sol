// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.6.6;

library SafeMathV2 {
  function add(uint x, uint y) internal pure returns (uint z) {
    require((z = x + y) >= x, 'ds-math-add-overflow');
  }

  function sub(uint x, uint y) internal pure returns (uint z) {
    require((z = x - y) <= x, 'ds-math-sub-underflow');
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
  }
}