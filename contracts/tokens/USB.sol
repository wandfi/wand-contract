// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IWandPoolFactory.sol";

contract USB is ERC20 {
  address public immutable wandPoolFactory;

  constructor(address _wandPoolFactory, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    require(_wandPoolFactory != address(0), "Zero address detected");
    wandPoolFactory = _wandPoolFactory;
  }

  function mint(address to, uint256 amount) public onlyWandPool {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public onlyWandPool {
    _burn(account, amount);
  }

  modifier onlyWandPool() {
    require(IWandPoolFactory(wandPoolFactory).isWandPool(_msgSender()), "Caller is not a WandPool contract");
    _;
  }
}