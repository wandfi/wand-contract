// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IPriceFeed.sol";

contract PriceFeedMock is IPriceFeed, Ownable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  string internal asset;
  uint8 internal priceDecimals;

  uint256 internal mockedPrice;
  uint256 internal mockedPriceTimestamp;
  
  EnumerableSet.AddressSet internal _testers;

  constructor(string memory _asset, uint8 _priceDecimals) Ownable() {
    asset = _asset;
    priceDecimals = _priceDecimals;

    _setTester(_msgSender(), true);
  }

  function decimals() external view override returns (uint8) {
    return priceDecimals;
  }

  function assetSymbol() external view override returns (string memory) {
    return asset;
  }

  function latestPrice() external view override returns (uint256, uint256) {
    return (mockedPrice, mockedPriceTimestamp);
  }

  function mockPrice(uint256 _mockPrice) external nonReentrant onlyTester {
    mockedPrice = _mockPrice;
    mockedPriceTimestamp = block.timestamp;
  }

  /* ================= Testers ================ */

  function getTestersCount() public view returns (uint256) {
    return _testers.length();
  }

  function getTester(uint256 index) public view returns (address) {
    require(index < _testers.length(), "Invalid index");
    return _testers.at(index);
  }

  function isTester(address account) public view returns (bool) {
    return _testers.contains(account);
  }

  function setTester(address account, bool minter) external nonReentrant onlyOwner {
    _setTester(account, minter);
  }

  function _setTester(address account, bool minter) internal {
    require(account != address(0), "Zero address detected");

    if (minter) {
      require(!_testers.contains(account), "Address is already tester");
      _testers.add(account);
    }
    else {
      require(_testers.contains(account), "Address was not tester");
      _testers.remove(account);
    }

    emit UpdaterTester(account, minter);
  }

  modifier onlyTester() {
    require(isTester(_msgSender()), "Caller is not tester");
    _;
  }

  /* ========== EVENTS ========== */

  event UpdaterTester(address indexed account, bool tester);
}