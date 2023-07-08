// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

interface IProtocolSettings {

  /* ============ VIEWS =========== */

  function decimals() external view returns (uint256);

  function defaultC1() external view returns (uint256);

  function defaultC2() external view returns (uint256);

  function assertC1(uint256 C1) external view;

  function assertC2(uint256 C2) external view;

  function assertY(uint256 Y) external view;

  function assertAART(uint256 targetAAR) external view;

  function assertAARS(uint256 safeAAR) external view;

  function assertAARC(uint256 safeAAR) external view;

  function defaultBasisR() external view returns (uint256);

  function assertBasisR(uint256 basisR) external view;

  function defaultRateR() external view returns (uint256);

  function assertRateR(uint256 rateR) external view;

  function defaultBasisR2() external view returns (uint256);

  function assertBasisR2(uint256 basisR2) external view;

  /* ============ MUTATIVE FUNCTIONS =========== */

  function setDefaultC1(uint256 defaultC1) external;

  function setDefaultC2(uint256 defaultC2) external;

  function setDefaultBasisR(uint256 newBasisR) external;

  function setDefaultRateR(uint256 newRateR) external;

  function setDefaultBasisR2(uint256 newBasisR2) external;

}