// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AssetX is ERC20 {
  address public wandPool;

  constructor(address _wandPool, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    require(_wandPool != address(0), "Zero address detected");
    wandPool = _wandPool;
  }

  function mint(address to, uint256 amount) public onlyWandPool {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public onlyWandPool {
    _burn(account, amount);
  }

  modifier onlyWandPool() {
    require(wandPool == _msgSender(), "Caller is not the WandPool contract");
    _;
  }
}