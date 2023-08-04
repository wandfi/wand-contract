// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICurvePool.sol";
import "./ERC20Mock.sol";

contract CurvePoolMock is ICurvePool {

  uint256 public constant N_COINS = 2;
  address[] public coins;

  ERC20Mock public immutable lpToken;

  // The fee rate (in percentage) for swapping in the pool
  uint256 public fee = 1;  // 1%

  // The constructor to initialize the contract with the token addresses
  constructor(address[N_COINS] memory _coins, address _poolToken) {
    coins = _coins;
    lpToken = ERC20Mock(_poolToken);
  }

  function balances(uint256 i) public view returns (uint256) {
    return IERC20(coins[i]).balanceOf(address(this));
  }

  // Deposit coins into the pool
  function add_liquidity(uint256[N_COINS] calldata _amounts, uint256 _min_mint_amount) external returns (uint256) {
    // Transfer the coins from the sender to the contract
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < coins.length; i++) {
      IERC20 coin = IERC20(coins[i]);
      coin.transferFrom(msg.sender, address(this), _amounts[i]);
      totalAmount += _amounts[i];
    }

    // Calculate the amount of LP tokens to mint
    // For simplicity, we use a 1:1 ratio between the coins and the LP token
    uint256 lpAmount = totalAmount / N_COINS;

    // Check the minimum mint amount is met
    require(lpAmount >= _min_mint_amount, "mint amount is too low");

    // Mint and transfer the LP tokens to the sender
    lpToken.mint(msg.sender, lpAmount);

    // Emit the deposit event
    emit Deposit(msg.sender, _amounts, lpAmount);

    // Return the amount of LP tokens minted
    return lpAmount;
  }

  // Withdraw coins from the pool
  function remove_liquidity(uint256 _amount, uint256[N_COINS] calldata _min_amounts) external {
    // Transfer the LP tokens from the sender to the contract
    lpToken.transferFrom(msg.sender, address(this), _amount);

    // Burn the LP tokens
    lpToken.burn(_amount);

    // Calculate the amounts of each coin to withdraw
    // For simplicity, we use a 1:1 ratio between the coins and the LP token
    uint256[N_COINS] memory amounts;
    for (uint256 i = 0; i < coins.length; i++) {
      amounts[i] = _amount / N_COINS;
      IERC20 coin = IERC20(coins[i]);
      coin.transfer(msg.sender, amounts[i]);

      require(amounts[i] >= _min_amounts[i], "withdraw amount of coin is too low");
    }

    // Emit the withdraw event
    emit Withdraw(msg.sender, amounts, _amount);
  }

  // Exchange coins in the pool
  function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external validIndex(i) validIndex(j) returns (uint256) { 
    // Choose which coins to swap based on the indices 
    IERC20 fromCoin = IERC20(coins[i]);
    IERC20 toCoin = IERC20(coins[j]);

    // Transfer the fromCoin from the sender to the contract
    fromCoin.transferFrom(msg.sender, address(this), dx);

    // Calculate the amount of toCoin to receive
    // For simplicity, we use a constant product formula with a fee
    uint256 dy = dx * balances(j) / (balances(i) * (100 - fee) / 100);

    // Check the minimum amount is met
    require(dy >= min_dy, "swap amount is too low");

    // Transfer the toCoin to the sender
    toCoin.transfer(msg.sender, dy);

    // Emit the exchange event
    emit Exchange(msg.sender, i, j, dx, dy);

    // Return the amount of toCoin received
    return dy;
  }

  // The modifier to check the index of the coin is valid
  modifier validIndex(uint256 i) {
    require(i == 0 || i == 1, "invalid coin index");
    _;
  }

  // The event emitted when coins are deposited into the pool
  event Deposit(address indexed sender, uint256[2] amounts, uint256 lpAmount);

  // The event emitted when coins are withdrawn from the pool
  event Withdraw(address indexed sender, uint256[2] amounts, uint256 lpAmount);

  // The event emitted when coins are exchanged in the pool
  event Exchange(address indexed sender, uint256 i, uint256 j, uint256 dx, uint256 dy);

}
