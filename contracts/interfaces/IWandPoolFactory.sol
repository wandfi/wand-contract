// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IWandPoolFactory {

  function isWandPool(address addr) external view returns (bool);
  
}