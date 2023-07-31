// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./InterestPool.sol";
import "../interfaces/IWandProtocol.sol";

contract UniLpInterestPool is InterestPool {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  uint256 internal _uniPoolCoinsUSBIndex = type(uint256).max;

  constructor(
    address _wandProtocol,
    address _interestPoolFactory,
    address _stakingToken,
    address[] memory _rewardTokens
  ) InterestPool(_wandProtocol, _interestPoolFactory, _stakingToken, _rewardTokens) {

    // Check `_stakingToken` is `IUniswapV2Pair`, and one of the tokens is $USB
    address usb = IWandProtocol(_wandProtocol).usbToken();
    IUniswapV2Pair pair = IUniswapV2Pair(_stakingToken);
    require(pair.token0() == usb || pair.token1() == usb, "Invalid Uniswap Lp staking token");
    _uniPoolCoinsUSBIndex = pair.token0() == usb ? 0 : 1;

    _stakingTokenInfo = Constants.InterestPoolStakingTokenInfo(
      _stakingToken,
      Constants.InterestPoolStakingTokenType.UniswapV2PairLp,
      _stakingToken,
      2
    );
  }

  function totalStakingAmountInUSB() public override view returns (uint256) {
    IERC20 lp = IERC20(_stakingTokenInfo.stakingToken);
    uint256 totalLpSupply = lp.totalSupply();
    if (totalLpSupply == 0) {
      return 0;
    }

    IUniswapV2Pair pool = IUniswapV2Pair(_stakingTokenInfo.swapPool);
    (uint256 reserve0, uint256 reserve1, ) = pool.getReserves();
    uint256 totalUSBAmountInPool = _uniPoolCoinsUSBIndex == 0 ? reserve0 : reserve1;
    return _totalStakingAmount.mul(totalUSBAmountInPool).div(totalLpSupply);
  }
}