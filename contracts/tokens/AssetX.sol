// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AssetX is ERC20 {
  address public assetPool;

  constructor(address _assetPool, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    require(_assetPool != address(0), "Zero address detected");
    assetPool = _assetPool;
  }

  function mint(address to, uint256 amount) public onlyAssetPool {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public onlyAssetPool {
    _burn(account, amount);
  }

  modifier onlyAssetPool() {
    require(assetPool == _msgSender(), "Caller is not the AssetPool contract");
    _;
  }
}