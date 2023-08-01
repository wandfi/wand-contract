// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./InterestPool.sol";

contract UsbInterestPool is InterestPool {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  constructor(
    address _wandProtocol,
    address _interestPoolFactory,
    address _stakingToken,
    address[] memory _rewardTokens
  ) InterestPool(_wandProtocol, _interestPoolFactory, _stakingToken, _rewardTokens) {
    _stakingTokenInfo = Constants.InterestPoolStakingTokenInfo(
      _stakingToken,
      Constants.InterestPoolStakingTokenType.Usb,
      address(0),
      0
    );
  }

  function totalStakingAmountInUSB() public override view returns (uint256) {
    return _totalStakingAmount;
  }
}
