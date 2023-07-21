// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IWandProtocol.sol";
import "../interfaces/IAssetPoolFactory.sol";

contract USB is ERC20 {
  address public immutable wandProtocol;

  constructor(address _wandProtocol, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;
  }

  function mint(address to, uint256 amount) public onlyAssetPool {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public onlyAssetPool {
    _burn(account, amount);
  }

  modifier onlyAssetPool() {
    require(IAssetPoolFactory(IWandProtocol(wandProtocol).assetPoolFactory()).isAssetPool(_msgSender()), "Caller is not an AssetPool contract");
    _;
  }
}