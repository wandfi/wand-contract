// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IAssetPool.sol";
import "../interfaces/IUSB.sol";
import "../libs/Constants.sol";

contract AssetPoolCalculator {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public immutable usbToken;

  struct Terms {
    uint256 T1;
    uint256 T2;
    uint256 T3;
    uint256 T4;
    uint256 T5;
    uint256 T6;
    uint256 T7;
    uint256 T8;
  }

  constructor(address _usbToken) {
    require(_usbToken != address(0), "Zero address detected");
    usbToken = _usbToken;
  }

  function AAR(IAssetPool assetPool, uint256 msgValue) public view returns (uint256) {
    if (assetPool.usbTotalSupply() == 0 && IERC20(assetPool.xToken()).totalSupply() == 0) {
      return 0;
    }
    else if (assetPool.usbTotalSupply() == 0 && IERC20(assetPool.xToken()).totalSupply() > 0) {
      return type(uint256).max;
    }

    uint256 assetTotalAmount = _getAssetTotalAmount(assetPool, msgValue);
    if (assetTotalAmount == 0) {
      return 0;
    }

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = assetPool.getAssetTokenPrice();
    return assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(10 ** assetPool.AARDecimals()).div(assetPool.usbTotalSupply());
  }

  function calculatePairedUSBAmountToRedeemByXTokens(IAssetPool assetPool, uint256 xTokenAmount) public view returns (uint256) {
    require(xTokenAmount > 0, "Amount must be greater than 0");
    require(IERC20(assetPool.xToken()).totalSupply() > 0, "No x tokens minted yet");

    // Δusb = Δethx * Musb-eth / M_ETHx
    return xTokenAmount.mul(assetPool.usbTotalSupply()).div(IERC20(assetPool.xToken()).totalSupply());
  }

  function calculateUSBToXTokensOut(Constants.AssetPoolState memory S, uint256 Delta_USB) public view returns (uint256) {
    // uint256 Delta_USB = usbAmount;
    require(Delta_USB > 0, "Amount must be greater than 0");
    require(Delta_USB < S.M_USB_ETH, "Too much $USB amount");

    // require(S.aar >= assetPool.AARC() || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= assetPool.CircuitBreakPeriod()), "AAR Below Circuit Breaker AAR Threshold");
    
    // AAR'eth = (M_ETH * P_ETH / (Musb-eth - Δusb)) * 100%
    S.aar_ = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.M_USB_ETH.sub(Delta_USB));
    S.r = r(S);

    // console.log('aar: %s, aa_: %s, r: %s, ', S.aar, S.aar_, S.r);
    // console.log('M_ETH: %s, P_ETH: %s', S.M_ETH, S.P_ETH);
    // console.log('M_USB_ETH: %s, M_ETHx: %s', S.M_USB_ETH, S.M_ETHx);
    // console.log('S.BasisR: %s, S.settingsDecimals: %s', S.BasisR, S.settingsDecimals);

    // If AAR'eth <= AAARS or AAReth >= S.AART
    //  Δethx = Δusb * M_ETHx * (1 + S.r) / (M_ETH * P_ETH - Musb-eth)
    if (S.aar_ <= S.AARS || S.aar >= S.AART) {
      return Delta_USB.mul(S.M_ETHx).mul((10 ** S.AARDecimals).add(S.r)).div(10 ** S.AARDecimals).div(
        S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)
      );
    }

    // If S.AARS <= AAR'eth <= S.AART, and AAReth <= S.AARS
    //  Δethx = (Musb-eth - M_ETH * P_ETH / S.AARS) * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + S.r) 
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / S.AARS) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    //    * (1 + (2 * S.AART - S.AARS - AAR'eth) * 0.1 / 2)
    if (S.aar_ >= S.AARS && S.aar_ <= S.AART && S.aar <= S.AARS) {
      Terms memory T;
      T.T1 = S.M_USB_ETH.sub(S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AARS)); // (Musb-eth - M_ETH * P_ETH / S.AARS)
      T.T2 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T3 = (10 ** S.AARDecimals).add(S.r);  // (1 + r)
      T.T4 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AARS).add(Delta_USB).sub(S.M_USB_ETH); // ((M_ETH * P_ETH / S.AARS) + Δusb - Musb-eth )
      T.T5 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T6 = uint256(2).mul(S.AART).sub(S.AARS).sub(S.aar_).mul(S.BasisR).div(2).div(10 ** S.settingsDecimals); // (2 * S.AART - S.AARS - AAR'eth) * 0.1 / 2

      return T.T1.mul(S.M_ETHx).div(T.T2).mul(T.T3).add(T.T4.mul(S.M_ETHx).div(T.T5).mul(
        (10 ** S.AARDecimals).add(T.T6))
      ).div(10 ** S.AARDecimals);
    }

    // If S.AARS <= AAReth <= S.AART, and S.AARS <= AAR'eth <= S.AART
    //  Δethx = Δusb * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (AAR'eth - AAReth) * 0.1 / 2)
    if (S.aar >= S.AARS && S.aar <= S.AART && S.aar_ >= S.AARS && S.aar_ <= S.AART) {
      return Delta_USB.mul(S.M_ETHx).div(S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH)) // Δusb * M_ETHx / (M_ETH * P_ETH - Musb-eth)
        .mul((10 ** S.AARDecimals).add(  // * (1 + (AAR'eth - AAReth) * 0.1 / 2)
          (S.aar_).sub(S.aar).mul(S.BasisR).div(2).div(10 ** S.settingsDecimals)
        )).div(10 ** S.AARDecimals);
    }

    // If AAR'eth >= S.AART, and AAReth <= S.AARS
    //  Δethx = (Musb-eth - M_ETH * P_ETH / S.AARS) * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + S.r)
    //    + (M_ETH * P_ETH / S.AARS - M_ETH * P_ETH / S.AART)
    //    * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (S.AART - S.AARS) * 0.1 / 2)
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / S.AART) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    if (S.aar_ >= S.AART && S.aar <= S.AARS) {
      Terms memory T;
      T.T1 = S.M_USB_ETH.sub(S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AARS)); // (Musb-eth - M_ETH * P_ETH / S.AARS)
      T.T2 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T3 = (10 ** S.AARDecimals).add(S.r);  // (1 + S.r)
      T.T4 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AARS)
        .sub(S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AART)); // (M_ETH * P_ETH / S.AARS - M_ETH * P_ETH / S.AART)
      T.T5 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T6 = (10 ** S.AARDecimals).add(S.AART.sub(S.AARS).mul(S.BasisR).div(2).div(10 ** S.settingsDecimals)); // (1 + (S.AART - S.AARS) * 0.1 / 2)
      T.T7 = (S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AART)).add(Delta_USB).sub(S.M_USB_ETH); // (M_ETH * P_ETH / S.AART + Δusb - Musb-eth)
      T.T8 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)

      return T.T1.mul(S.M_ETHx).div(T.T2).mul(T.T3).div(10 ** S.AARDecimals).add(
        T.T4.mul(S.M_ETHx).div(T.T5).mul(T.T6).div(10 ** S.AARDecimals)
      )
      .add(
        T.T7.mul(S.M_ETHx).div(T.T8)
      );
    }

    // If AAR'eth >= S.AART, and S.AARS <= AAReth <= S.AART
    //  Δethx = (Musb-eth - M_ETH * P_ETH / S.AART) 
    //      * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    //      * (1 + (S.AART - AAReth) * 0.1 / 2)
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / S.AART) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    if (S.aar_ >= S.AART && S.aar >= S.AARS && S.aar <= S.AART) {
      Terms memory T;
      T.T1 = S.M_USB_ETH.sub(S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AART)); // (Musb-eth - M_ETH * P_ETH / S.AART)
      T.T2 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)
      T.T3 = (10 ** S.AARDecimals).add(S.AART.sub(S.aar).mul(S.BasisR).div(2).div(10 ** S.settingsDecimals)); // (1 + (S.AART - AAReth) * 0.1 / 2)
      T.T4 = (S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(S.AART)).add(Delta_USB).sub(S.M_USB_ETH); // (M_ETH * P_ETH / S.AART + Δusb - Musb-eth)
      T.T5 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.M_USB_ETH); // (M_ETH * P_ETH - Musb-eth)

      return T.T1.mul(S.M_ETHx).div(T.T2).mul(T.T3).div(10 ** S.AARDecimals).add(T.T4.mul(S.M_ETHx).div(T.T5));
    }

    revert("Should not reach here");
  }

  // 𝑟 = 0 𝑖𝑓 𝐴𝐴𝑅 ≥ 2
  // 𝑟 = assetPool.BasisR() × (𝐴𝐴𝑅𝑇 − 𝐴𝐴𝑅) 𝑖𝑓 1.5 <= 𝐴𝐴𝑅 < 2;
  // 𝑟 = assetPool.BasisR() × (𝐴𝐴𝑅𝑇 − 𝐴𝐴𝑅S) + assetPool.RateR() × 𝑡(h𝑟𝑠) 𝑖𝑓 𝐴𝐴𝑅 < 1.5;
  function r(Constants.AssetPoolState memory S) public view returns (uint256) {
    if (S.aar < S.AARS) {
      Terms memory T;
      T.T1 = S.AART.sub(S.AARS).mul(S.BasisR).div(10 ** S.settingsDecimals);
      T.T2 = S.aarBelowSafeLineTime == 0 ? 0 : block.timestamp.sub(S.aarBelowSafeLineTime);
      return T.T1.add(S.RateR.mul(T.T2).div(1 hours));
    } 
    else if (S.aar < S.AART) {
      return  S.AART.sub(S.aar).mul(S.BasisR).div(10 ** S.settingsDecimals);
    }
    return 0;
  }

  function calculateMintUSBOut(Constants.AssetPoolState memory S, uint256 assetAmount) public view returns (uint256) {
    require(assetAmount > 0, "Amount must be greater than 0");

    require(S.aar >= S.AARS, "AAR Below Safe Threshold");
    
    uint256 Delta_ETH = assetAmount;

    // Special case (initial mint): If AAR'eth = max, Δusb = Δeth * P_ETH
    if (S.aar == type(uint256).max) {
      return Delta_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    }

    // AAR'eth = (Δeth + M_ETH)* P_ETH / (Musb-eth + Δeth * P_ETH)) * 100%
    S.aar_ = Delta_ETH.add(S.M_ETH).mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(10 ** S.AARDecimals).div(
      S.M_USB_ETH.add(Delta_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS))
    );

    // console.log('aar: %s, aa_: %s, r: %s, ', S.aar, S.aar_, S.r);
    // console.log('M_ETH: %s, P_ETH: %s', S.M_ETH, S.P_ETH);
    // console.log('M_USB_ETH: %s, M_ETHx: %s', S.M_USB_ETH, S.M_ETHx);
    // console.log('S.BasisR2: %s, S.settingsDecimals: %s', S.BasisR2, S.settingsDecimals);

    require(S.aar_ >= S.AARS, "AAR Below Safe Threshold after Mint");

    // If AAR'eth >= S.AART, and AAReth >= S.AART
    //  Δusb = Δeth * P_ETH
    if (S.aar_ >= S.AART && S.aar >= S.AART) {
      return Delta_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS);
    }

    // If S.AARS <= AAR'eth <= S.AART, and AAReth >= S.AART
    //  Δusb = (M_ETH * P_ETH - S.AART * Musb-eth) / (S.AART - 1)
    //    + (Δeth * P_ETH - (M_ETH * P_ETH - S.AART * Musb-eth) / (S.AART - 1))
    //      * (1 - (S.AART - AAR'eth) * 0.06 / 2)
    if (S.aar_ >= S.AARS && S.aar_ <= S.AART && S.aar >= S.AART) {
      Terms memory T;
      T.T1 = S.M_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(S.AART.mul(S.M_USB_ETH).div(10 ** S.AARDecimals)); // (M_ETH * P_ETH - S.AART * Musb-eth)
      T.T2 = S.AART.sub(10 ** S.AARDecimals); // (S.AART - 1)
      T.T3 = Delta_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).sub(T.T1.mul(10 ** S.AARDecimals).div(T.T2)); // (Δeth * P_ETH - (M_ETH * P_ETH - S.AART * Musb-eth) / (S.AART - 1))
      T.T4 = (10 ** S.settingsDecimals).sub(
        S.AART.sub(S.aar_).mul(S.BasisR2).div(2).div(10 ** S.settingsDecimals)
      ); // (1 - (S.AART - AAR'eth) * 0.06 / 2)

      return T.T1.mul(10 ** S.AARDecimals).div(T.T2).add(T.T3.mul(T.T4).div((10 ** S.settingsDecimals)));
    }

    // If S.AARS <= AAR'eth <= S.AART, and S.AARS <= AAReth <= S.AART
    //  Δusb = Δeth * P_ETH * (1 - (AAReth - AAR'eth) * 0.06 / 2)
    if (S.aar_ >= S.AARS && S.aar_ <= S.AART && S.aar >= S.AARS && S.aar <= S.AART) {
      return Delta_ETH.mul(S.P_ETH).div(10 ** S.P_ETH_DECIMALS).mul(
        (10 ** S.AARDecimals).sub(
          S.aar.sub(S.aar_).mul(S.BasisR2).div(2).div(10 ** S.settingsDecimals)
        )
      ).div(10 ** S.AARDecimals);
    }

    revert("Should not reach here");
  }

  function calculateMintXTokensOut(IAssetPool assetPool, uint256 assetAmount, uint256 msgValue) public view returns (uint256) {
    uint256 aar = AAR(assetPool, msgValue);
    require(assetPool.usbTotalSupply() == 0 || IERC20(assetPool.xToken()).totalSupply() == 0 || aar > 10 ** assetPool.AARDecimals(), "AAR Below 100%");
    // console.log('calculateMintXTokensOut, _aarBelowCircuitBreakerLineTime: %s, now: %s', _aarBelowCircuitBreakerLineTime, block.timestamp);
    // require(aar >= assetPool.AARC() || (block.timestamp.sub(_aarBelowCircuitBreakerLineTime) >= assetPool.CircuitBreakPeriod()), "AAR Below Circuit Breaker AAR Threshold");

    (uint256 assetTokenPrice, uint256 assetTokenPriceDecimals) = assetPool.getAssetTokenPrice();

    // Initial mint: Δethx = Δeth
    uint256 xTokenAmount = assetAmount;

    // Otherwise: Δethx = (Δeth * P_ETH * M_ETHx) / (M_ETH * P_ETH - Musb-eth)
    if (IERC20(assetPool.xToken()).totalSupply() > 0) {
      uint256 assetTotalAmount = _getAssetTotalAmount(assetPool, msgValue);

      uint256 xTokenTotalAmount = IERC20(assetPool.xToken()).totalSupply();

      Terms memory T;
      T.T1 = assetAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).mul(xTokenTotalAmount); // (Δeth * P_ETH * M_ETHx)
      T.T2 = assetTotalAmount.mul(assetTokenPrice).div(10 ** assetTokenPriceDecimals).sub(assetPool.usbTotalSupply()); // (M_ETH * P_ETH - Musb-eth)
      xTokenAmount = T.T1.div(T.T2);
    }

    return xTokenAmount;
  }

  function _getAssetTotalAmount(IAssetPool assetPool, uint256 msgValue) internal view returns (uint256) {
    // console.log('_getAssetTotalAmount, msg.value: %s', msg.value);
    address assetToken = assetPool.getAssetToken();

    if (assetToken == Constants.NATIVE_TOKEN) {
      return address(assetPool).balance.sub(msgValue);
    }
    else {
      return IERC20(assetToken).balanceOf(address(assetPool));
    }
  }
}