// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LeveragedToken is Ownable, ERC20, ReentrancyGuard {
  using SafeMath for uint256;

  address public vault;

  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

  /* ========== RESTRICTED FUNCTIONS ========== */

  function mint(address to, uint256 amount) public nonReentrant onlyVault {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public nonReentrant onlyVault {
    _burn(account, amount);
  }

  function setVault(address _vault) external nonReentrant onlyOwner {
    require(vault == address(0), "Vault already set");
    require(_vault != address(0), "Zero address detected");

    vault = _vault;
    emit SetVault(vault);
  }

  /* ============== MODIFIERS =============== */

  modifier onlyVault() {
    require(vault != address(0) && vault == _msgSender(), "Caller is not Vault");
    _;
  }

  /* =============== EVENTS ============= */

  event SetVault(address indexed vault);
}