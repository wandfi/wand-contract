// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./InterestPool.sol";

contract InterestPoolFactory is Context, ReentrancyGuard {
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

  function getInterestPoolAddress(address stakingToken) public virtual view returns (address) {
    require(_interestPoolsByStakingToken[stakingToken] != address(0), 'InterestPool does not exist');
    return _interestPoolsByStakingToken[stakingToken];
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function addInterestPool(address stakingToken, InterestPool.StakingTokenType stakingTokenType, address[] memory rewardTokens) external nonReentrant onlyProtocol {
    require(stakingToken != address(0), "Zero address detected");
    require(_interestPoolsByStakingToken[stakingToken] == address(0), "InterestPool already exists");

    address pool = address(new InterestPool(wandProtocol, address(this), stakingToken, stakingTokenType, rewardTokens));
    _interestPoolsByStakingToken[stakingToken] = pool;

    emit InterestPoolAdded(stakingToken, stakingTokenType, rewardTokens, pool);
  }

  function addInterestRewards(address stakingToken, address rewardToken, uint256 amount) external nonReentrant onlyAssetPool  {
    require(amount > 0, "Reward amount should be greater than 0");
    require(stakingToken != address(0), "Zero address detected");
    require(_stakingTokens.contains(stakingToken), "Invalid staking token");

    InterestPool(_interestPoolsByStakingToken[stakingToken]).addRewards(rewardToken, amount);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyProtocol() {
    require(_msgSender() == wandProtocol, "Caller is not protocol");
    _;
  }

  modifier onlyAssetPool() {
    require(IAssetPoolFactory(WandProtocol(wandProtocol).assetPoolFactory()).isAssetPool(_msgSender()), "Caller is not an AssetPool contract");
    _;
  }

  /* =============== EVENTS ============= */

  event InterestPoolAdded(address indexed stakingToken, InterestPool.StakingTokenType stakingTokenType, address[] rewardTokens, address interestPool);

}