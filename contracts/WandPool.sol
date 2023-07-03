// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./tokens/AssetX.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IWandPool.sol";

contract WandPool is IWandPool, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable wandPoolFactory;
    address public immutable assetToken;
    address public immutable assetTokenPriceFeed;
    address public immutable xToken;

    constructor(
      address _wandPoolFactory,
      address _assetToken,
      address _assetTokenPriceFeed,
      string memory _xTokenName,
      string memory _xTokenSymbol
    ) {
      require(_wandPoolFactory != address(0), "Zero address detected");
      require(_assetToken != address(0), "Zero address detected");
      require(_assetTokenPriceFeed != address(0), "Zero address detected");
      wandPoolFactory = _wandPoolFactory;
      assetToken = _assetToken;
      assetTokenPriceFeed = _assetTokenPriceFeed;
      xToken = address(new AssetX(address(this), _xTokenName, _xTokenSymbol));
    }

    function mint(uint256 amount) external payable override nonReentrant {

    }

    modifier onlyWandPoolFactory() {
      require(msg.sender == wandPoolFactory, "Caller is not WandPoolFactory");
      _;
    }
}