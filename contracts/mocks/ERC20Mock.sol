// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ERC20Mock is ERC20, ERC20Burnable, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _minters;

  constructor(
    string memory name,
    string memory symbol
  ) Ownable() ERC20(name, symbol) {
    _setMinter(_msgSender(), true);
  }

  /* ================= VIEWS ================ */

  function getMintersCount() public view returns (uint256) {
    return _minters.length();
  }

  function getMinter(uint256 index) public view returns (address) {
    require(index < _minters.length(), "Invalid index");
    return _minters.at(index);
  }

  function isMinter(address account) public view returns (bool) {
    return _minters.contains(account);
  }

  /* ================= MUTATIVE FUNCTIONS ================ */

  function setMinter(address account, bool minter) external nonReentrant onlyOwner {
    _setMinter(account, minter);
  }

  function mint(address to, uint256 value) public nonReentrant onlyMinter returns (bool) {
    _mint(to, value);
    return true;
  }

    /* ========== INTERNAL FUNCTIONS ========== */

  function _setMinter(address account, bool minter) internal {
    require(account != address(0), "Zero address detected");

    if (minter) {
      require(!_minters.contains(account), "Address is already minter");
      _minters.add(account);
    }
    else {
      require(_minters.contains(account), "Address was not minter");
      _minters.remove(account);
    }

    emit UpdateMinter(account, minter);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyMinter() {
    require(isMinter(_msgSender()), "Caller is not minter");
    _;
  }

  /* ========== EVENTS ========== */

  event UpdateMinter(address indexed account, bool minter);
}