// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../contracts/mocks/ERC20Mock.sol";

contract ERC20MockTest is Test {
  ERC20Mock t;

  function setUp() public {
    t = new ERC20Mock("ERC20 Mock", "ERC20");
  }

  function testName() public {
    assertEq(t.name(), "ERC20 Mock");
  }
}