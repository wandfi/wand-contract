// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "hardhat/console.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./UsbInterestPool.sol";
import "./UniLpInterestPool.sol";
import "./CurveLpInterestPool.sol";
import "../interfaces/IWandProtocol.sol";
import "../interfaces/IAssetPoolFactory.sol";
import "../interfaces/IInterestPool.sol";
import "../interfaces/IInterestPoolFactory.sol";

contract InterestPoolFactory is IInterestPoolFactory, Context, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  address public immutable wandProtocol;

  EnumerableSet.AddressSet private _stakingTokens;
  mapping(address => address) private _interestPoolsByStakingToken;

  constructor(address _wandProtocol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
  }

  /* ============== VIEWS =============== */

  /**
   * @dev No guarantees are made on the ordering
   */
  function stakingTokens() public view returns (address[] memory) {
    return _stakingTokens.values();
  }

  function poolExists(address stakingToken) public view returns (bool) {
    return _interestPoolsByStakingToken[stakingToken] != address(0);
  }

  function getInterestPoolAddress(address stakingToken) public view returns (address) {
    require(poolExists(stakingToken), 'InterestPool does not exist');
    return _interestPoolsByStakingToken[stakingToken];
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function addInterestPool(
    address stakingToken, Constants.InterestPoolStakingTokenType stakingTokenType,
    address swapPool, uint256 swapPoolCoinsCount, address[] memory rewardTokens
  ) external nonReentrant onlyProtocol {
    require(stakingToken != address(0), "Zero address detected");
    require(_interestPoolsByStakingToken[stakingToken] == address(0), "InterestPool already exists");

    address pool;
    if (stakingTokenType == Constants.InterestPoolStakingTokenType.Usb) {
      pool = address(new UsbInterestPool(wandProtocol, address(this), stakingToken, rewardTokens));
    }
    else if (stakingTokenType == Constants.InterestPoolStakingTokenType.UniswapV2PairLp) {
      pool = address(new UniLpInterestPool(wandProtocol, address(this), stakingToken, rewardTokens));
    }
    else if (stakingTokenType == Constants.InterestPoolStakingTokenType.CurvePlainPoolLp) {
      pool = address(new CurveLpInterestPool(wandProtocol, address(this), stakingToken, swapPool, swapPoolCoinsCount, rewardTokens));
    }
    else {
      revert("Invalid staking token type");
    }
    
    _stakingTokens.add(stakingToken);
    _interestPoolsByStakingToken[stakingToken] = pool;

    emit InterestPoolAdded(stakingToken, stakingTokenType, rewardTokens, pool);
  }

  function addRewardToken(address stakingToken, address rewardToken) public nonReentrant onlyProtocol {
    require(_stakingTokens.contains(stakingToken), "Invalid staking token");
    IInterestPool(_interestPoolsByStakingToken[stakingToken]).addRewardToken(rewardToken);
  }

  function addRewardTokenToAllPools(address rewardToken) public nonReentrant onlyProtocol {
    require(rewardToken != address(0), "Zero address detected");
    // console.log('InterestPoolFactory, addRewardTokenToAllPools for x token : %s', ERC20(rewardToken).symbol());

    for (uint256 i = 0; i < _stakingTokens.length(); i++) {
      if (!IInterestPool(_interestPoolsByStakingToken[_stakingTokens.at(i)]).rewardTokenAdded(rewardToken)) {
        IInterestPool(_interestPoolsByStakingToken[_stakingTokens.at(i)]).addRewardToken(rewardToken);
      }
    }
  }

  function distributeInterestRewards(address rewardToken, uint256 totalAmount) public nonReentrant onlyAssetPool returns (bool) {
    require(rewardToken != address(0), "Zero address detected");
    require(totalAmount > 0, "Reward amount should be greater than 0");

    uint256 totalStakingAmountInUSB = 0;
    for (uint256 i = 0; i < _stakingTokens.length(); i++) {
      IInterestPool pool = IInterestPool(_interestPoolsByStakingToken[_stakingTokens.at(i)]);
      if (pool.rewardTokenAdded(rewardToken)) {
        totalStakingAmountInUSB = totalStakingAmountInUSB.add(pool.totalStakingAmountInUSB());
      }
    }

    if (totalStakingAmountInUSB == 0) {
      return false;
    }
    for (uint256 i = 0; i < _stakingTokens.length(); i++) {
      IInterestPool pool = IInterestPool(_interestPoolsByStakingToken[_stakingTokens.at(i)]);
      if (pool.rewardTokenAdded(rewardToken)) {
        uint256 amount = totalAmount.mul(pool.totalStakingAmountInUSB()).div(totalStakingAmountInUSB);
        if (amount > 0) {
          require(
            IERC20(rewardToken).transferFrom(_msgSender(), address(pool), amount),
            'InterestPoolFactory::distributeInterestRewards: transfer reward token failed'
          );
          pool.notifyRewardsAdded(rewardToken, amount);
        }
      }
    }

    return true;
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  modifier onlyAssetPool() {
    require(IAssetPoolFactory(IWandProtocol(wandProtocol).assetPoolFactory()).isAssetPool(_msgSender()), "Caller is not an AssetPool contract");
    _;
  }

  /* =============== EVENTS ============= */

  event InterestPoolAdded(address indexed stakingToken, Constants.InterestPoolStakingTokenType stakingTokenType, address[] rewardTokens, address interestPool);

}