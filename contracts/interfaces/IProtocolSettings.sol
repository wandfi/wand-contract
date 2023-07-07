// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IProtocolSettings {

  /* ============ VIEWS =========== */

  function decimals() external view returns (uint256);

  function defaultC1() external view returns (uint256);

  function defaultC2() external view returns (uint256);

  function defaultY() external view returns (uint256);

  function assertC1(uint256 C1) external view;

  function assertC2(uint256 C2) external view;

  function assertY(uint256 Y) external view;

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setDefaultC1(uint256 defaultC1) external;

  function setDefaultC2(uint256 defaultC2) external;

  function setDefaultY(uint256 defaultY) external;

}