// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface ICurvePool {

  function coins(uint256 i) external view returns (address);

  function balances(uint256 i) external view returns (uint256);

  function get_virtual_price() external view returns (uint256);

}
