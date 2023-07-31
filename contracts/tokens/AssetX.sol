// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IWandProtocol.sol";
import "../interfaces/IProtocolSettings.sol";

contract AssetX is Ownable, ERC20, ReentrancyGuard {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  address public immutable wandProtocol;
  address public assetPool;

  uint256 public fee;
  uint256 public feeDecimals;

  // addresses free of transfer fee
  EnumerableSet.AddressSet internal _whitelistAddresses;

  constructor(address _wandProtocol, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    require(_wandProtocol != address(0), "Zero address detected");
    wandProtocol = _wandProtocol;

    IProtocolSettings settings = IProtocolSettings(IWandProtocol(wandProtocol).settings());
    feeDecimals = settings.decimals();
    fee = settings.paramDefaultValue("XTokensTransferFee");
  }

  /* ================= VIEWS ================ */

  function getWhitelistAddressesLength() external view returns (uint256) {
    return _whitelistAddresses.length();
  }

  function getWhitelistAddress(uint256 index) external view returns (address) {
    require(index < _whitelistAddresses.length(), "getWhitelistAddress: invalid index");
    return _whitelistAddresses.at(index);
  }

  function isAddressWhitelisted(address account) external view returns (bool) {
    return _whitelistAddresses.contains(account);
  }

  /* ================= MUTATIVE FUNCTIONS ================ */

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    address from = _msgSender();
    if (fee == 0 || _whitelistAddresses.contains(from) || _whitelistAddresses.contains(to)) {
      _transfer(from, to, amount);
      return true;
    }

    return _transferWithFees(from, to, amount);
  }

  function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    address spender = _msgSender();
    _spendAllowance(from, spender, amount);
    if (fee == 0 || _whitelistAddresses.contains(from) || _whitelistAddresses.contains(to)) {
      _transfer(from, to, amount);
      return true;
    }

    return _transferWithFees(from, to, amount);
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function mint(address to, uint256 amount) public onlyAssetPool {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) public onlyAssetPool {
    _burn(account, amount);
  }

  function setFee(uint256 newFee) external nonReentrant onlyOwner {
    require(newFee != fee, "Same transfer fee");
    
    uint256 prevFee = fee;
    fee = newFee;
    emit UpdatedFee(prevFee, fee);
  }

  /**
   * @dev Adds or removes addresses from the whitelist
   */
  function setWhitelistAddress(address account, bool whitelisted) external nonReentrant onlyOwner {
    _setWhitelistAddress(account, whitelisted);
  }

  function setAssetPool(address _assetPool) external nonReentrant onlyOwner {
    require(_assetPool != address(0), "Zero address detected");
    assetPool = _assetPool;
    _setWhitelistAddress(_assetPool, true);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _setWhitelistAddress(address account, bool whitelisted) internal {
    require(account != address(0), "Zero address detected");

    if (whitelisted) {
      require(!_whitelistAddresses.contains(account), "Address already whitelisted");
      _whitelistAddresses.add(account);
    }
    else {
      require(_whitelistAddresses.contains(account), "Address not whitelisted");
      _whitelistAddresses.remove(account);
    }

    emit UpdateWhitelistAddress(account, whitelisted);
  }

  function _transferWithFees(address from, address to, uint256 amount) internal returns (bool) {
    uint256 feeAmount = amount.mul(fee).div(10 ** feeDecimals);
    uint256 remainingAmount = amount.sub(feeAmount);
    address treasury = IProtocolSettings(IWandProtocol(wandProtocol).settings()).treasury();

    _transfer(from, to, remainingAmount);
    _transfer(from, treasury, feeAmount);
    emit TransferFeeCollected(from, treasury, feeAmount);
    return true;
  }

  /* ============== MODIFIERS =============== */

  modifier onlyAssetPool() {
    require(assetPool != address(0) && assetPool == _msgSender(), "Caller is not the AssetPool contract");
    _;
  }

  /* =============== EVENTS ============= */

  event UpdatedFee(uint256 prevFee, uint256 newFee);
  event UpdateWhitelistAddress(address account, bool whitelisted);
  event TransferFeeCollected(address indexed from, address indexed to, uint256 value);
}