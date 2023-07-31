// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./InterestPool.sol";
import "../interfaces/IWandProtocol.sol";
import "../interfaces/ICurvePool.sol";

contract CurveLpInterestPool is InterestPool {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  uint256 internal _curvePoolCoinsUSBIndex = type(uint256).max;

  constructor(
    address _wandProtocol,
    address _interestPoolFactory,
    address _stakingToken,
    address _curvePool,
    uint256 _curvePoolCoinsCount,
    address[] memory _rewardTokens
  ) InterestPool(_wandProtocol, _interestPoolFactory, _stakingToken, _rewardTokens) {

    // Check one of the curve pool token is $USB
    require(_curvePoolCoinsCount > 0, "Invalid curve pool coins count");
    address usb = IWandProtocol(_wandProtocol).usbToken();
    ICurvePool curvePool = ICurvePool(_curvePool);
    for (uint256 i = 0; i < _curvePoolCoinsCount; i++) {
      if (curvePool.coins(i) == usb) {
        _curvePoolCoinsUSBIndex = i;
        break;
      }
    }
    require(_curvePoolCoinsUSBIndex != type(uint256).max, "Invalid Curve Lp staking token");

    _stakingTokenInfo = Constants.InterestPoolStakingTokenInfo(
      _stakingToken,
      Constants.InterestPoolStakingTokenType.UniswapV2PairLp,
      _curvePool,
      _curvePoolCoinsCount
    );
  }

  function totalStakingAmountInUSB() public override view returns (uint256) {
    IERC20 lp = IERC20(_stakingTokenInfo.stakingToken);
    uint256 totalLpSupply = lp.totalSupply();
    if (totalLpSupply == 0) {
      return 0;
    }

    ICurvePool pool = ICurvePool(_stakingTokenInfo.swapPool);
    uint256 totalUSBAmountInPool = pool.balances(_curvePoolCoinsUSBIndex);
    return _totalStakingAmount.mul(totalUSBAmountInPool).div(totalLpSupply);
  }
}