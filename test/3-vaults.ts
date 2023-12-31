import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  maxContractSize, nativeTokenAddress, PtyPoolType, ONE_DAY_IN_SECS,
  deployContractsFixture, dumpContracts, dumpVaultState, expectBigNumberEquals
} from './utils';
import { 
  LeveragedToken__factory,
  PtyPool__factory
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Vaults', () => {

  async function deployVaultsAndPtyPoolsFixture() {
    
    const {
      Alice, Bob, Caro, usb, stETH, wbtc, ethPriceFeed, stethPriceFeed, wbtcPriceFeed,
      wandProtocol, settings, vaultCalculator
    } = await loadFixture(deployContractsFixture);

    // Create $ETHx token
    const LeveragedTokenFactory = await ethers.getContractFactory('LeveragedToken');
    expect(LeveragedTokenFactory.bytecode.length / 2).lessThan(maxContractSize);
    const ETHx = await LeveragedTokenFactory.deploy("ETHx Token", "ETHx");
    const ethx = LeveragedToken__factory.connect(ETHx.address, provider);
    
    // Create ETH vault
    const ethAddress = nativeTokenAddress;
    const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(2).div(100);  // 2.0%
    const ethAARU = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(130).div(100);  // 130%
    const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%

    const Vault = await ethers.getContractFactory('Vault');
    const ethVault = await Vault.deploy(wandProtocol.address, vaultCalculator.address, ethAddress, ethPriceFeed.address, ethx.address,
        [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AARU"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
        [ethY, ethAARU, ethAART, ethAARS, ethAARC]);
    await expect(wandProtocol.connect(Alice).addVault(ethVault.address))
      .to.emit(wandProtocol, 'VaultAdded').withArgs(ethAddress, ethPriceFeed.address, ethVault.address);

    // Connect $ETHx with ETH vault
    await expect(ethx.connect(Bob).setVault(ethVault.address)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(ethx.connect(Alice).setVault(ethVault.address))
      .to.emit(ethx, 'SetVault').withArgs(ethVault.address);

    // Create PtyPools for $ETH vault
    const PtyPoolFactory = await ethers.getContractFactory('PtyPool');
    const EthVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(ethVault.address, PtyPoolType.RedeemByUsbBelowAARS, ethx.address, nativeTokenAddress);
    const ethVaultPtyPoolBelowAARS = PtyPool__factory.connect(EthVaultPtyPoolBelowAARS.address, provider);
    const EthVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(ethVault.address, PtyPoolType.MintUsbAboveAARU, nativeTokenAddress, ethx.address);
    const ethVaultPtyPoolAboveAARU = PtyPool__factory.connect(EthVaultPtyPoolAboveAARU.address, provider);
    let trans = await ethVault.connect(Alice).setPtyPools(ethVaultPtyPoolBelowAARS.address, ethVaultPtyPoolAboveAARU.address);
    await trans.wait();

    // Create $stETH vault
    const stETHxToken = await LeveragedTokenFactory.deploy("stETHx Token", "stETHx");
    const stethx = LeveragedToken__factory.connect(stETHxToken.address, provider);
    const stETHY = BigNumber.from(10).pow(await settings.decimals()).mul(2).div(100);  // 2%
    const stETHAARU = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const stETHAART = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const stETHAARS = BigNumber.from(10).pow(await settings.decimals()).mul(130).div(100);  // 130%
    const stETHAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%

    const stethVault = await Vault.deploy(wandProtocol.address, vaultCalculator.address, stETH.address, stethPriceFeed.address, stethx.address,
        [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AARU"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
        [stETHY, stETHAARU, stETHAART, stETHAARS, stETHAARC]);
    await expect(wandProtocol.connect(Alice).addVault(stethVault.address))
      .to.emit(wandProtocol, 'VaultAdded').withArgs(stETH.address, stethPriceFeed.address, stethVault.address);

    // Connect $stethx with $stETH vault
    await expect(stethx.connect(Bob).setVault(stethVault.address)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(stethx.connect(Alice).setVault(stethVault.address))
      .to.emit(stethx, 'SetVault').withArgs(stethVault.address);
    
    // Create PtyPools for $stETH vault
    const stETHVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(stethVault.address, PtyPoolType.RedeemByUsbBelowAARS, stethx.address, stETH.address);
    const stethVaultPtyPoolBelowAARS = PtyPool__factory.connect(stETHVaultPtyPoolBelowAARS.address, provider);
    const stETHVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(stethVault.address, PtyPoolType.MintUsbAboveAARU, stETH.address, stethx.address);
    const stethVaultPtyPoolAboveAARU = PtyPool__factory.connect(stETHVaultPtyPoolAboveAARU.address, provider);
    trans = await stethVault.connect(Alice).setPtyPools(stethVaultPtyPoolBelowAARS.address, stethVaultPtyPoolAboveAARU.address);
    await trans.wait();

    // Create $WBTC vault
    const WBTCx = await LeveragedTokenFactory.deploy("WBTCx Token", "WBTCx");
    const wbtcx = LeveragedToken__factory.connect(WBTCx.address, provider);
    const wbtcY = BigNumber.from(10).pow(await settings.decimals()).mul(30).div(1000);  // 3%
    const wbtcAARU = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const wbtcAART = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const wbtcAARS = BigNumber.from(10).pow(await settings.decimals()).mul(130).div(100);  // 130%
    const wbtcAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%

    const wbtcVault = await Vault.deploy(wandProtocol.address, vaultCalculator.address, wbtc.address, wbtcPriceFeed.address, wbtcx.address,
        [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AARU"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
        [wbtcY, wbtcAARU, wbtcAART, wbtcAARS, wbtcAARC]);
    await expect(wandProtocol.connect(Alice).addVault(wbtcVault.address))
      .to.emit(wandProtocol, 'VaultAdded').withArgs(wbtc.address, wbtcPriceFeed.address, wbtcVault.address);

    // Connect $WBTCx with WBTC vault
    await expect(wbtcx.connect(Alice).setVault(wbtcVault.address))
      .to.emit(wbtcx, 'SetVault').withArgs(wbtcVault.address);

    // Create PtyPools for $WBTC vault
    const WBTCVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(wbtcVault.address, PtyPoolType.RedeemByUsbBelowAARS, wbtcx.address, wbtc.address);
    const wbtcVaultPtyPoolBelowAARS = PtyPool__factory.connect(WBTCVaultPtyPoolBelowAARS.address, provider);
    const WBTCVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(wbtcVault.address, PtyPoolType.MintUsbAboveAARU, wbtc.address, wbtcx.address);
    const wbtcVaultPtyPoolAboveAARU = PtyPool__factory.connect(WBTCVaultPtyPoolAboveAARU.address, provider);
    trans = await wbtcVault.connect(Alice).setPtyPools(wbtcVaultPtyPoolBelowAARS.address, wbtcVaultPtyPoolAboveAARU.address);
    await trans.wait();

    return {
      Alice, Bob, Caro, usb, stETH, wbtc, ethPriceFeed, stethPriceFeed, wbtcPriceFeed,
      wandProtocol, settings, vaultCalculator,
      ethVault, ethx, ethVaultPtyPoolBelowAARS, ethVaultPtyPoolAboveAARU,
      stethVault, stethx, stethVaultPtyPoolBelowAARS, stethVaultPtyPoolAboveAARU,
      wbtcVault, wbtcx, wbtcVaultPtyPoolBelowAARS, wbtcVaultPtyPoolAboveAARU
    };
  }

  it('Vault Mint & Redeem & Conditional Discount Purchase Works', async () => {

    const {
      Alice, Bob, Caro, usb, ethPriceFeed,
      wandProtocol, vaultCalculator,
      ethVault, ethx
    } = await loadFixture(deployVaultsAndPtyPoolsFixture);

    await dumpContracts(wandProtocol.address);

    // Initial AAR should be 0
    expect (await ethVault.AAR()).to.equal(0);

    // Set Y & C to 0 to facilitate testing
    await expect(ethVault.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("Y"), 0))
      .to.emit(ethVault, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("Y"), 0);
    await expect(ethVault.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("C"), 0))
      .to.emit(ethVault, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("C"), 0);

    /**
     * Vault State: M_ETH = 0, M_USB = 0, M_ETHx = 0, P_ETH = $2000
     * Alice deposit 2 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH_i * 1 / AART = 2 * 2000 * 1 / 150% = 2666.7
     *  ΔETHx = ΔETH * (1 - 1 / AART) = 2 * (1 - 1 / 150%) = 0.6667
     */
    let ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpVaultState(ethVault);
    let ethDepositAmount = ethers.utils.parseEther('2');
    let expectedUsbAmount = ethers.utils.parseUnits('2666.666666666666666666', await usb.decimals());
    let expectedEthxAmount = ethers.utils.parseUnits('0.666666666666666666', await ethx.decimals());
    let calcOut = await vaultCalculator.calcMintPairsAtStabilityPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut[1]);
    expectBigNumberEquals(expectedEthxAmount, calcOut[2]);
    await expect(ethVault.connect(Alice).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Vault State:
     *  M_ETH: 2.0
     *  P_ETH: 2000.0
     *  P_ETH_i: 2000.0
     *  M_USB: 2666.666666666666666666
     *  M_USB_ETH: 2666.666666666666666666
     *  M_ETHx: 0.666666666666666666
     *  AAR: 150.00%
     *  APY: 0.00%
     *  Phase: Stability
     * Set ETH price to $2200
     * Bob deposit 1 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH_i * 1 / AART = 1 * 2000 * 1 / 150% = 1333.3
     *  ΔETHx = ΔETH * (1 - 1 / AART) = 1 * (1 - 1 / 150%) = 0.3333
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('2200', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('1');
    expectedUsbAmount = ethers.utils.parseUnits('1333.333333333333333333', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('0.333333333333333333', await ethx.decimals());
    calcOut = await vaultCalculator.calcMintPairsAtStabilityPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut[1]);
    expectBigNumberEquals(expectedEthxAmount, calcOut[2]);
    await expect(ethVault.connect(Bob).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Bob, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Bob, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Bob, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Bob.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Bob.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Vault State:
     *  M_ETH: 3.0
     *  P_ETH: 2200.0
     *  P_ETH_i: 2000.0
     *  M_USB: 3999.999999999999999999
     *  M_USB_ETH: 3999.999999999999999999
     *  M_ETHx: 0.999999999999999999
     *  AAR: 165.00%
     *  APY: 0.00%
     *  Phase: Stability
     * Set ETH price to $1800
     * Caro deposit 4 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH_i * 1 / AART = 4 * 2000 * 1 / 150% = 5333.333333333333333333
     *  ΔETHx = ΔETH * (1 - 1 / AART) = 4 * (1 - 1 / 150%) = 1.333333333333333333
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('1800', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('4');
    expectedUsbAmount = ethers.utils.parseUnits('5333.333333333333333333', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('1.333333333333333333', await ethx.decimals());
    calcOut = await vaultCalculator.calcMintPairsAtStabilityPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut[1]);
    expectBigNumberEquals(expectedEthxAmount, calcOut[2]);
    await expect(ethVault.connect(Caro).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Caro, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Caro, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Caro, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Caro.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Caro.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Vault State:
     *  M_ETH: 7.0
     *  P_ETH: 1800.0
     *  P_ETH_i: 2000.0
     *  M_USB: 9333.333333333333333332
     *  M_USB_ETH: 9333.333333333333333332
     *  M_ETHx: 2.333333333333333332
     *  AAR: 135.00%
     *  APY: 0.00%
     *  Phase: Stability
     * 
     * Set ETH price to $3000
     * Alice deposit 4 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH_i * 1 / AART = 4 * 2000 * 1 / 150% = 5333.333333333333333333
     *  ΔETHx = ΔETH * (1 - 1 / AART) = 4 * (1 - 1 / 150%) = 1.333333333333333333
     */
    await dumpVaultState(ethVault);
    await expect(vaultCalculator.calcMintPairsAtAdjustmentPhase(ethVault.address, ethDepositAmount)).to.be.revertedWith("Vault not at adjustment phase");
    await expect(vaultCalculator.calcMintUsbAboveAARU(ethVault.address, ethDepositAmount)).to.be.revertedWith("Vault not at adjustment above AARU phase");
    await expect(vaultCalculator.calcMintLeveragedTokensBelowAARS(ethVault.address, ethDepositAmount)).to.be.revertedWith("Vault not at adjustment below AARS phase");
    ethPrice = ethers.utils.parseUnits('3000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('4');
    expectedUsbAmount = ethers.utils.parseUnits('5333.333333333333333333', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('1.333333333333333333', await ethx.decimals());
    calcOut = await vaultCalculator.calcMintPairsAtStabilityPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut[1]);
    expectBigNumberEquals(expectedEthxAmount, calcOut[2]);
    await expect(ethVault.connect(Alice).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Vault State:
     *  M_ETH: 11.0
     *  P_ETH: 3000.0
     *  P_ETH_i: 2000.0
     *  M_USB: 14666.666666666666666665
     *  M_USB_ETH: 14666.666666666666666665
     *  M_ETHx: 3.666666666666666665
     *  AAR: 225.00%
     *  APY: 0.00%
     *  Phase: AdjustmentAboveAARU
     * 
     * Alice deposit 1 ETH to mint $USB
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH = 1 * 3000 * = 3000
     */
    await dumpVaultState(ethVault);
    ethDepositAmount = ethers.utils.parseEther('1');
    expectedUsbAmount = ethers.utils.parseUnits('3000', await usb.decimals());
    let calcOut2 = await vaultCalculator.calcMintUsbAboveAARU(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut2[1]);
    await expect(ethVault.connect(Alice).mintUSBAboveAARU(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, 0)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
   
    /**
     * Vault State:
     *  M_ETH: 12.0
     *  P_ETH: 3000.0
     *  P_ETH_i: 2000.0
     *  M_USB: 17666.666666666666666665
     *  M_USB_ETH: 17666.666666666666666665
     *  M_ETHx: 3.666666666666666665
     *  AAR: 203.773585%
     *  APY: 0.00%
     *  Phase: AdjustmentAboveAARU
     * 
     * Alice deposit 1 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH * 1 / AAR = 1 * 3000 / 203.773585% = 1472.22222154
     *  ΔETHx = ΔETH * P_ETH * M_ETHx / (AAR * Musb-eth) = 1 * 3000 * 3.666666666666666665 / (203.773585% * 17666.666666666666666665) = 0.30555555541
     */
    await dumpVaultState(ethVault);
    ethDepositAmount = ethers.utils.parseEther('1');
    expectedUsbAmount = ethers.utils.parseUnits('1472.22222154', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('0.30555555541', await ethx.decimals());
    calcOut = await vaultCalculator.calcMintPairsAtAdjustmentPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut[1]);
    expectBigNumberEquals(expectedEthxAmount, calcOut[2], );
    let prevUsbBlance = await usb.balanceOf(Alice.address);
    let prevEthxBlance = await ethx.balanceOf(Alice.address);
    await expect(ethVault.connect(Alice).mintPairsAtAdjustmentPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      // .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      // .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, anyValue, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
    let usbBlance = await usb.balanceOf(Alice.address);
    let ethxBlance = await ethx.balanceOf(Alice.address);
    expectBigNumberEquals(prevUsbBlance.add(expectedUsbAmount), usbBlance);
    expectBigNumberEquals(prevEthxBlance.add(expectedEthxAmount), ethxBlance);

    /**
     * Vault State:
     *  M_ETH: 12.0
     *  P_ETH: 3000.0
     *  P_ETH_i: 2000.0
     *  M_USB: 17666.666666666666666665
     *  M_USB_ETH: 17666.666666666666666665
     *  M_ETHx: 3.972222222230709874
     *  AAR: 203.773585%
     *  APY: 0.00%
     *  Phase: AdjustmentAboveAARU
     * 
     * Set ETH price to $1800
     * Alice deposit 1 ETH to mint $USB
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH = 1 * 1800 * = 1800
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('1800', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('1');
    expectedUsbAmount = ethers.utils.parseUnits('1800', await usb.decimals());
    calcOut2 = await vaultCalculator.calcMintUsbAboveAARU(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut2[1]);
    await expect(ethVault.connect(Alice).mintUSBAboveAARU(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, 0)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
   
    /**
     * Vault State:
     *  M_ETH: 14.0
     *  P_ETH: 1800.0
     *  P_ETH_i: 2000.0
     *  M_USB: 20938.888888929783950616
     *  M_USB_ETH: 20938.888888929783950616
     *  M_ETHx: 3.972222222230709874
     *  AAR: 120.350226%
     *  APY: 0.00%
     *  Phase: AdjustmentBelowAARS
     *  AARBelowSafeLineTime: > 0
     *  AARBelowCircuitBreakerLineTime: 0
     * 
     * Alice deposit 1 ETH to mint $ETHx
     * Expected out:
     *  ΔETHx = ΔETH * P_ETH * M_ETHx / (M_ETH * P_ETH - Musb-eth) = 1 * 1800 * 3.972222222230709874 / (14 * 1800 - 20938.888888929783950616) ~= 1.677966101714604555
     */
    await dumpVaultState(ethVault);
    ethDepositAmount = ethers.utils.parseEther('1');
    expectedEthxAmount = ethers.utils.parseUnits('1.677966101714604555', await usb.decimals());
    calcOut2 = await vaultCalculator.calcMintLeveragedTokensBelowAARS(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedEthxAmount, calcOut2[1]);
    await expect(ethVault.connect(Alice).mintLeveragedTokensBelowAARS(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, 0)
      .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
 
    /**
     * Vault State:
     *  M_ETH: 15.0
     *  P_ETH: 1800.0
     *  P_ETH_i: 2000.0
     *  M_USB: 20938.888888929783950616
     *  M_USB_ETH: 20938.888888929783950616
     *  M_ETHx: 5.650188323945314429
     *  AAR: 128.94667%
     *  APY: 0.00%
     *  Phase: AdjustmentBelowAARS
     *  AARBelowSafeLineTime: > 0
     *  AARBelowCircuitBreakerLineTime: 0
     * 
     * Set ETH price to $1500, AAR = 107.455559%
     * Alice deposit 1 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH * 1 / AAR = 1 * 1500 / 107.455559% = 1395.92591948
     *  ΔETHx = ΔETH * P_ETH * M_ETHx / (AAR * Musb-eth) = 1 * 1500 * 5.650188323945314429 / (107.455559% * 20938.888888929783950616) = 0.37667921985
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('1500', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('1');
    expectedUsbAmount = ethers.utils.parseUnits('1395.92591948', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('0.37667921985', await ethx.decimals());
    calcOut = await vaultCalculator.calcMintPairsAtAdjustmentPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(expectedUsbAmount, calcOut[1]);
    expectBigNumberEquals(expectedEthxAmount, calcOut[2]);
    prevUsbBlance = await usb.balanceOf(Alice.address);
    prevEthxBlance = await ethx.balanceOf(Alice.address);
    await expect(ethVault.connect(Alice).mintPairsAtAdjustmentPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, anyValue, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
    usbBlance = await usb.balanceOf(Alice.address);
    ethxBlance = await ethx.balanceOf(Alice.address);
    expectBigNumberEquals(prevUsbBlance.add(expectedUsbAmount), usbBlance);
    expectBigNumberEquals(prevEthxBlance.add(expectedEthxAmount), ethxBlance);
    
    /**
     * Vault State:
     *  M_ETH: 16.0
     *  P_ETH: 1500.0
     *  P_ETH_i: 2000.0
     *  M_USB: 22334.814814902240740741
     *  M_USB_ETH: 22334.814814902240740741
     *  M_ETHx: 6.026867545553489018
     *  AAR: 107.455559%
     *  APY: 0.00%
     *  Phase: AdjustmentBelowAARS
     *  AARBelowSafeLineTime: > 0
     *  AARBelowCircuitBreakerLineTime: > 0
     * 
     *  $USB -> $ETHx swap is paused for 1 hour
     *  Alice swap 1000 $USB to $ETHx after 4 hours
     * Expected out:
     *  r = 0.001 * 4 = 0.004
     *  ΔETHx = ΔUSB * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth) = 1000 * 6.026867545553489018 * (1 + 0.004) / (16 * 1500 - 22334.814814902240740741) = 3.63381506747
     */
    await dumpVaultState(ethVault);
    let usbSwapAmount = ethers.utils.parseUnits('1000', await usb.decimals());
    await expect(vaultCalculator.calcUsbToLeveragedTokens(ethVault.address, usbSwapAmount)).to.be.revertedWith("Conditional Discount Purchase suspended");
    await expect(ethVault.connect(Alice).usbToLeveragedTokens(usbSwapAmount)).to.be.revertedWith("Conditional Discount Purchase suspended");
    await time.increase(1 * 60 * 60);
    await expect(vaultCalculator.calcUsbToLeveragedTokens(ethVault.address, usbSwapAmount)).not.to.be.reverted;
    await time.increase(3 * 60 * 60);
    let usbAmount = ethers.utils.parseUnits('1000', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('3.63381506747', await ethx.decimals());
    calcOut2 = await vaultCalculator.calcUsbToLeveragedTokens(ethVault.address, usbAmount);
    expectBigNumberEquals(expectedEthxAmount, calcOut2[1]);
    // expectedEthxAmount = calcOut2[1];
    await expect(ethVault.connect(Alice).usbToLeveragedTokens(usbAmount))
      .to.changeTokenBalance(usb, Alice, usbAmount.mul(-1))
      // .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'UsbBurned').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, 0, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'UsbToLeveragedTokens').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals());

    /**
     * Vault State:
     *  M_ETH: 16.0
     *  P_ETH: 1500.0
     *  P_ETH_i: 2000.0
     *  M_USB: 21334.814814902240740741
     *  M_USB_ETH: 21334.814814902240740741
     *  M_ETHx: 9.660686634469412429
     *  AAR: 112.492188%
     *  APY: 0.00%
     *  Phase: AdjustmentBelowAARS
     *  AARBelowSafeLineTime: > 0
     *  AARBelowCircuitBreakerLineTime: 0
     *  
     * Set ETH price to $1200, AAR drop below 100%
     * Alice redeems $1000 $USB
     * Expected out:
     *  ΔETH = ΔUSB * M_ETH / Musb-eth = 1000 * 16 / 21334.814814902240740741 = 0.74994792028
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('1200', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    usbAmount = ethers.utils.parseUnits('1000', await usb.decimals());
    let expectedEthOut = ethers.utils.parseEther('0.74994792028');
    calcOut2 = await vaultCalculator.calcRedeemByUsbBelowAARS(ethVault.address, usbAmount);
    expectBigNumberEquals(expectedEthOut, calcOut2[1]);
    let prevEthBalance = await provider.getBalance(Alice.address);
    await expect(ethVault.connect(Alice).redeemByUsbBelowAARS(usbAmount))
      .to.changeTokenBalance(usb, Alice, usbAmount.mul(-1))
      // .to.changeEtherBalance(Alice, expectedEthOut)
      .to.emit(ethVault, 'UsbBurned').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'AssetRedeemedWithUSB').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
    expectBigNumberEquals(prevEthBalance.add(expectedEthOut), await provider.getBalance(Alice.address));

    /**
     * Vault State:
     *  M_ETH: 15.250052079719759483
     *  P_ETH: 1200.0
     *  P_ETH_i: 2000.0
     *  M_USB: 20334.814814902240740741
     *  M_USB_ETH: 20334.814814902240740741
     *  M_ETHx: 9.660686634469412429
     *  AAR: 89.99375%
     *  APY: 0.00%
     *  Phase: AdjustmentBelowAARS
     *  AARBelowSafeLineTime: > 0
     *  AARBelowCircuitBreakerLineTime: > 0
     *  
     * Set ETH price to $2100, AAR ~= 112%
     * Alice redeems $1000 $USB
     * Expected out:
     *  ΔETH = ΔUSB / P_ETH = 1000 / 2100 = 0.47619047619
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('2100', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    usbAmount = ethers.utils.parseUnits('1000', await usb.decimals());
    expectedEthOut = ethers.utils.parseEther('0.47619047619');
    calcOut2 = await vaultCalculator.calcRedeemByUsbBelowAARS(ethVault.address, usbAmount);
    expectBigNumberEquals(expectedEthOut, calcOut2[1]);
    prevEthBalance = await provider.getBalance(Alice.address);
    await expect(ethVault.connect(Alice).redeemByUsbBelowAARS(usbAmount))
      .to.changeTokenBalance(usb, Alice, usbAmount.mul(-1))
      .to.emit(ethVault, 'UsbBurned').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'AssetRedeemedWithUSB').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
    expectBigNumberEquals(prevEthBalance.add(expectedEthOut), await provider.getBalance(Alice.address));

    /**
     * Vault State:
     *  M_ETH: 14.773861603529283293
     *  P_ETH: 2100.0
     *  P_ETH_i: 2100.0
     *  M_USB: 19334.814814902240740741
     *  M_USB_ETH: 19334.814814902240740741
     *  M_ETHx: 9.660686634469412429
     *  AAR: 160.462408%
     *  APY: 0.00%
     *  Phase: Stability
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     *  
     * Alice redeems $1000 $USB
     * Expected out:
     *  Paired ΔETHx = ΔUSB * M_ETHx / Musb-eth = 1000 * 9.660686634469412429 / 19334.814814902240740741 = 0.49965240044
     *  ΔETH = ΔETHx * M_ETH / M_ETHx = 0.49965240044 * 14.773861603529283293 / 9.660686634469412429 = 0.7641067031
     */
    await dumpVaultState(ethVault);
    usbAmount = ethers.utils.parseUnits('1000', await usb.decimals());
    expectedEthxAmount = ethers.utils.parseUnits('0.49965240044', await ethx.decimals());
    expectedEthOut = ethers.utils.parseEther('0.7641067031');
    expectBigNumberEquals(expectedEthxAmount, await vaultCalculator.calcPairdLeveragedTokenAmount(ethVault.address, usbAmount));
    calcOut2 = await vaultCalculator.calcPairedRedeemAssetAmount(ethVault.address, expectedEthxAmount);
    expectBigNumberEquals(expectedEthOut, calcOut2[1]);
    prevEthBalance = await provider.getBalance(Alice.address);
    prevEthxBlance = await ethx.balanceOf(Alice.address);
    await expect(ethVault.connect(Alice).redeemByPairsWithExpectedUSBAmount(usbAmount))
      .to.changeTokenBalance(usb, Alice, usbAmount.mul(-1))
      .to.emit(ethVault, 'UsbBurned').withArgs(Alice.address, usbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenBurned').withArgs(Alice.address, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'AssetRedeemedWithPairs').withArgs(Alice.address, usbAmount, anyValue, anyValue, ethPrice, await ethPriceFeed.decimals());
    expectBigNumberEquals(prevEthBalance.add(expectedEthOut), await provider.getBalance(Alice.address));
    expectBigNumberEquals(prevEthxBlance.sub(expectedEthxAmount), await ethx.balanceOf(Alice.address));

    /**
     * Vault State:
     *  M_ETH: 14.773861603529283293
     *  P_ETH: 2100.0
     *  P_ETH_i: 2100.0
     *  M_USB: 19334.814814902240740741
     *  M_USB_ETH: 19334.814814902240740741
     *  M_ETHx: 9.660686634469412429
     *  AAR: 160.462408%
     *  APY: 0.00%
     *  Phase: Stability
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     *  
     * Alice redeems 1 $ETHx
     * Expected out:
     *  Paired ΔUSB = ΔETHx * Musb-eth / M_ETHx = 1 * 19334.814814902240740741 / 9.660686634469412429 = 2001.39136549
     *  ΔETH = ΔETHx * M_ETH / M_ETHx = 1 * 14.773861603529283293 / 9.660686634469412429 = 1.52927655792
     */
    await dumpVaultState(ethVault);
    let ethxAmount = ethers.utils.parseUnits('1', await ethx.decimals());
    expectedUsbAmount = ethers.utils.parseUnits('2001.39136549', await usb.decimals());
    expectedEthOut = ethers.utils.parseEther('1.52927655792');
    expectBigNumberEquals(expectedUsbAmount, await vaultCalculator.calcPairedUsbAmount(ethVault.address, ethxAmount));
    calcOut2 = await vaultCalculator.calcPairedRedeemAssetAmount(ethVault.address, ethxAmount);
    expectBigNumberEquals(expectedEthOut, calcOut2[1]);
    prevEthBalance = await provider.getBalance(Alice.address);
    prevUsbBlance = await usb.balanceOf(Alice.address);
    await expect(ethVault.connect(Alice).redeemByPairsWithExpectedLeveragedTokenAmount(ethxAmount))
      .to.changeTokenBalance(ethx, Alice, ethxAmount.mul(-1))
      .to.emit(ethVault, 'UsbBurned').withArgs(Alice.address, anyValue, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenBurned').withArgs(Alice.address, ethxAmount, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'AssetRedeemedWithPairs').withArgs(Alice.address, anyValue, ethxAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
    expectBigNumberEquals(prevEthBalance.add(expectedEthOut), await provider.getBalance(Alice.address));
    expectBigNumberEquals(prevUsbBlance.sub(expectedUsbAmount), await usb.balanceOf(Alice.address));

    /**
     * Vault State:
     *  M_ETH: 12.480478342493062243
     *  P_ETH: 2100.0
     *  P_ETH_i: 2100.0
     *  M_USB: 16333.423449415293225911
     *  M_USB_ETH: 16333.423449415293225911
     *  M_ETHx: 8.161034234022138837
     *  AAR: 160.462408%
     *  APY: 0.00%
     *  Phase: Stability
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     *  
     * Set ETH price to $2800, AAR ~= 213%
     * Alice deposits 0.1 $ETH to mint $USB and $ETHx, also updating vault state to AdjustmentAboveAARU
     * 
     * Vault State:
     *  M_ETH: 12.580478342493062243
     *  P_ETH: 2800.0
     *  P_ETH_i: 2100.0
     *  M_USB: 16473.423449415293225911
     *  M_USB_ETH: 16473.423449415293225911
     *  M_ETHx: 8.19436756735547217
     *  AAR: 213.831323%
     *  APY: 0.00%
     *  Phase: AdjustmentAboveAARU
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     * 
     * Alice redeems 1 $ETHx
     * Expected out:
     *  ΔETH = ΔETHx * (M_ETH * P_ETH - Musb-eth) / (M_ETHx * P_ETH) = 1 * (12.580478342493062243 * 2800 - 16473.423449415293225911) / (8.19436756735547217 * 2800) = 0.81728245283
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('2800', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('0.1');
    await expect(ethVault.connect(Alice).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount})).not.to.be.reverted;
    await dumpVaultState(ethVault);
    ethxAmount = ethers.utils.parseUnits('1', await ethx.decimals());
    expectedEthOut = ethers.utils.parseEther('0.81728245283');
    calcOut2 = await vaultCalculator.calcRedeemByLeveragedTokenAboveAARU(ethVault.address, ethxAmount);
    expectBigNumberEquals(expectedEthOut, calcOut2[1]);
    prevEthBalance = await provider.getBalance(Alice.address);
    prevEthxBlance = await ethx.balanceOf(Alice.address);
    await expect(ethVault.connect(Alice).redeemByLeveragedTokenAboveAARU(ethxAmount))
      .to.changeTokenBalance(ethx, Alice, ethxAmount.mul(-1))
      .to.emit(ethVault, 'LeveragedTokenBurned').withArgs(Alice.address, ethxAmount, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'AssetRedeemedWithLeveragedToken').withArgs(Alice.address, ethxAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
    expectBigNumberEquals(prevEthBalance.add(expectedEthOut), await provider.getBalance(Alice.address));
    expectBigNumberEquals(prevEthxBlance.sub(ethxAmount), await ethx.balanceOf(Alice.address));


  });

  it('Vault Fees & Price Trigger Yields Works', async () => {

    const {
      Alice, Bob, Caro, usb, stETH, wbtc, ethPriceFeed, stethPriceFeed, wbtcPriceFeed,
      wandProtocol, vaultCalculator, ethVault, ethx, stethVault, stethx, wbtcVault, wbtcx,
      ethVaultPtyPoolBelowAARS, ethVaultPtyPoolAboveAARU, stethVaultPtyPoolBelowAARS, stethVaultPtyPoolAboveAARU
    } = await loadFixture(deployVaultsAndPtyPoolsFixture);

    await dumpContracts(wandProtocol.address);

    // Day 0
    const genesisTime = await time.latest();

    stETH.connect(Alice).mint(Alice.address, ethers.utils.parseUnits('100', await stETH.decimals()));
    stETH.connect(Alice).mint(Bob.address, ethers.utils.parseUnits('100', await stETH.decimals()));
    wbtc.connect(Alice).mint(Alice.address, ethers.utils.parseUnits('100', await wbtc.decimals()));
    wbtc.connect(Alice).mint(Bob.address, ethers.utils.parseUnits('100', await wbtc.decimals()));

    /**
     * Set $ETH price to $2000, $stETH price to $2000, $WBTC price to $30000
     * Alice depoist 10 ETH to ethVault, 10 stETH to stethVault, 10 WBTC to wbtcVault
     */
    let ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    let stethPrice = ethers.utils.parseUnits('2000', await stethPriceFeed.decimals());
    await expect(stethPriceFeed.connect(Alice).mockPrice(stethPrice)).not.to.be.reverted;
    let wbtcPrice = ethers.utils.parseUnits('30000', await wbtcPriceFeed.decimals());
    await expect(wbtcPriceFeed.connect(Alice).mockPrice(wbtcPrice)).not.to.be.reverted;
    stETH.connect(Alice).approve(stethVault.address, ethers.utils.parseUnits('10', await stETH.decimals()));
    wbtc.connect(Alice).approve(wbtcVault.address, ethers.utils.parseUnits('10', await wbtc.decimals()));
    await expect(ethVault.connect(Alice).mintPairsAtStabilityPhase(ethers.utils.parseEther('10'), {value: ethers.utils.parseEther('10')})).not.to.be.reverted;
    await expect(stethVault.connect(Alice).mintPairsAtStabilityPhase(ethers.utils.parseEther('10'))).not.to.be.reverted;
    await expect(wbtcVault.connect(Alice).mintPairsAtStabilityPhase(ethers.utils.parseEther('10'))).not.to.be.reverted;

    /**
     * $ETH / $stETH Vault State:
     *  M_ETH: 10
     *  P_ETH: 2000.0
     *  P_ETH_i: 2000.0
     *  M_USB: 226666.666666666666666666
     *  M_USB_ETH: 13333.333333333333333333
     *  M_ETHx: 3.333333333333333333
     *  AAR: 150%
     *  APY: 2.00%
     *  Phase: Stability
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     * 
     * $ETH Vault:
     *  PtyPoolBelowAARS: Alice stakes 100000 $USB, Bob stakes 10000 $USB
     *  PtyPoolAboveAARU: Alice stakes 1 $ETH, Bob stakes 0.5 $ETH
     */
    await dumpVaultState(ethVault);
    // await dumpVaultState(stethVault);
    await expect(usb.connect(Alice).transfer(Bob.address, ethers.utils.parseUnits('15000', await usb.decimals()))).not.to.be.reverted;
    await expect(usb.connect(Alice).approve(ethVaultPtyPoolBelowAARS.address, ethers.utils.parseUnits('100000', await usb.decimals()))).not.to.be.rejected;
    await expect(ethVaultPtyPoolBelowAARS.connect(Alice).stake(ethers.utils.parseUnits('100000', await usb.decimals()))).not.to.be.reverted;
    await expect(usb.connect(Bob).approve(ethVaultPtyPoolBelowAARS.address, ethers.utils.parseUnits('10000', await usb.decimals()))).not.to.be.rejected;
    await expect(ethVaultPtyPoolBelowAARS.connect(Bob).stake(ethers.utils.parseUnits('10000', await usb.decimals()))).not.to.be.reverted;
    await expect(ethVaultPtyPoolAboveAARU.connect(Alice).stake(ethers.utils.parseEther('1'), {value: ethers.utils.parseUnits('1')})).not.to.be.reverted;
    await expect(ethVaultPtyPoolAboveAARU.connect(Bob).stake(ethers.utils.parseEther('0.5'), {value: ethers.utils.parseUnits('0.5')})).not.to.be.reverted;

    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 10);

    /**
     * 10 days later, Bob deposit 10 $ETH:
     *  $ETH yields (ΔETH): 10 * 2% * 10 / 365 = 0.00547945205
     *  $USB yields:  ΔUSB = ΔETH * P_ETH_i * 1 / AART_eth = 0.00547945205 * 2000 * 1 / 150% = 7.30593606667
     *  $ETHx yeilds: ΔETHx = ΔETH * (1 - 1 / AART_eth) = ΔETH * (AART_eth - 1) / AART_eth = 0.00547945205 * (150% - 100%) / 150% = 0.00182648401
     *  PtyPoolBelowAARS:
     *    Staking yields added: ΔETHx / 2 = 0.000913242005
     *  PtyPoolAboveAARU:
     *    Matching yields added: ΔETHx / 2 = 0.000913242005
     * 
     * Bob's mint out:
     *  ΔUSB = ΔETH * P_ETH_i * 1 / AART = 10 * 2000 * 1 / 150% = 13333.3333333
     *  ΔETHx = ΔETH * (1 - 1 / AART) = 10 * (1 - 1 / 150%) = 3.33333333333
     */
    let expectedRebasedUsb = ethers.utils.parseUnits('7.30593606667', await usb.decimals());
    let expectedPtyPoolBelowAARSStakingYields = ethers.utils.parseUnits('0.000913242005', await ethx.decimals());
    let expectedPtyPoolAboveAARUMatchingYields = ethers.utils.parseUnits('0.000913242005', await ethx.decimals());
    let ethDepositAmount = ethers.utils.parseEther('10');
    let expectedUsbAmount = ethers.utils.parseUnits('13333.3333333', await usb.decimals());
    let expectedEthxAmount = ethers.utils.parseUnits('3.33333333333', await ethx.decimals());
    let calcOut = await vaultCalculator.calcMintPairsAtStabilityPhase(ethVault.address, ethDepositAmount);
    let usbTotalSupply = await usb.totalSupply();
    let usbAliceBalance = await usb.balanceOf(Alice.address);
    let usbPtyPoolBelowAARSBalance = await usb.balanceOf(ethVaultPtyPoolBelowAARS.address);
    await expect(ethVault.connect(Bob).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.emit(ethVault, 'YieldsSettlement').withArgs(anyValue, anyValue)
      .to.emit(ethVaultPtyPoolBelowAARS, 'StakingYieldsAdded').withArgs(anyValue)
      .to.emit(ethVaultPtyPoolAboveAARU, 'MatchingYieldsAdded').withArgs(anyValue);
    expectBigNumberEquals(usbTotalSupply.add(expectedUsbAmount).add(expectedRebasedUsb), await usb.totalSupply());
    expectBigNumberEquals(usbAliceBalance.add(usbAliceBalance.mul(expectedRebasedUsb).div(usbTotalSupply)), await usb.balanceOf(Alice.address));
    // console.log(usbAliceBalance, await usb.balanceOf(Alice.address));
    expectBigNumberEquals(usbPtyPoolBelowAARSBalance.add(usbPtyPoolBelowAARSBalance.mul(expectedRebasedUsb).div(usbTotalSupply)), await usb.balanceOf(ethVaultPtyPoolBelowAARS.address));
    expectBigNumberEquals(expectedPtyPoolBelowAARSStakingYields, await ethx.balanceOf(ethVaultPtyPoolBelowAARS.address));
    expectBigNumberEquals(expectedPtyPoolAboveAARUMatchingYields, await ethx.balanceOf(ethVaultPtyPoolAboveAARU.address));
    expectBigNumberEquals(expectedPtyPoolBelowAARSStakingYields.mul(10).div(11), await ethVaultPtyPoolBelowAARS.earnedStakingYields(Alice.address));
    expectBigNumberEquals(expectedPtyPoolBelowAARSStakingYields.mul(1).div(11), await ethVaultPtyPoolBelowAARS.earnedStakingYields(Bob.address));

    /**
     * $ETH / $stETH Vault State:
     *  M_ETH: 20
     *  P_ETH: 2000.0
     *  P_ETH_i: 2000.0
     *  M_USB: 240007.305859969558598665
     *  M_USB_ETH: 26667.478428885506510962
     *  M_ETHx: 6.668493131659056315
     *  AAR: 149.995434%
     *  APY: 2.00%
     *  Phase: Stability
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     * 
     * $ETH Vault:
     *  PtyPoolBelowAARS: Alice stakes 100000 $USB, Bob stakes 10000 $USB
     *    Total staking yields: 0.000913242005 $ETHx
     *  PtyPoolAboveAARU: Alice stakes 1 $ETH, Bob stakes 0.5 $ETH
     *    Total matching yields: 0.000913242005 $ETHx
     * 
     * 10 days later, $ETH price drop to 1500:
     *  AAR = 20 * 1500 / 240007.305859969558598665 = 124.998958%
     * 
     * Alice redeems with 1000 $USB and xx $ETHx
     *  $ETH yields (ΔETH): 20 * 2% * 10 / 365 = 0.0109589041
     *  $USB yields:  ΔUSB = ΔETH * P_ETH_i * 1 / AART_eth = 0.0109589041 * 2000 * 1 / 150% = 14.6118721333
     *  $ETHx yeilds: ΔETHx = ΔETH * (1 - 1 / AART_eth) = ΔETH * (AART_eth - 1) / AART_eth = 0.0109589041 * (150% - 100%) / 150% = 0.00365296803
     *  PtyPoolBelowAARS:
     *    Staking yields added: 0.000913242005 + 0.00182648401 = 0.002739726015
     *  PtyPoolAboveAARU:
     *    Matching yields added: 0.000913242005 + 0.00182648401 = 0.002739726015
     * 
     * After Alice's redeem, AAR drop below AARS, triggering PtyPoolBelowAARS match:
     *    ΔUSB: 10901.007386
     *    Matching Asset (ΔETH): 7.26733825735
     */
    await dumpVaultState(ethVault);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 20);
    let usbAmount = ethers.utils.parseUnits('1000', await usb.decimals());
    let pairedEthxAmount = await vaultCalculator.calcPairdLeveragedTokenAmount(ethVault.address, usbAmount);
    ethPrice = ethers.utils.parseUnits('1500', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    usbTotalSupply = await usb.totalSupply();
    await expect(ethVault.connect(Alice).redeemByPairsWithExpectedUSBAmount(usbAmount))
      .to.emit(ethVault, 'YieldsSettlement').withArgs(anyValue, anyValue)
      .to.emit(ethVaultPtyPoolBelowAARS, 'StakingYieldsAdded').withArgs(anyValue)
      .to.emit(ethVaultPtyPoolAboveAARU, 'MatchingYieldsAdded').withArgs(anyValue)
      .to.emit(ethVaultPtyPoolBelowAARS, 'MatchedTokensAdded').withArgs(anyValue);
    console.log(usbTotalSupply, await usb.totalSupply());

   /**
     * $ETH / $stETH Vault State:
     *  M_ETH: 6.41197322825562447
     *  P_ETH: 1500.0.0
     *  P_ETH_i: 1500.0
     *  M_USB: 219764.843363146745089355
     *  M_USB_ETH: 6411.973228255624469238
     *  M_ETHx: 6.422085227838380214
     *  AAR: 150.00%
     *  APY: 2.00%
     *  Phase: Stability
     *  AARBelowSafeLineTime: 0
     *  AARBelowCircuitBreakerLineTime: 0
     *
     * Set $ETH price to $2100, AAR > AARU
     * Alice redeems 1 $ETHx, triggering PtyPoolAboveAARU match
     * 
     */
    await dumpVaultState(ethVault);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 21);
    ethPrice = ethers.utils.parseUnits('2100', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    let ethxAmount = ethers.utils.parseUnits('1', await ethx.decimals());
    let pairedUsbAmount = await vaultCalculator.calcPairedUsbAmount(ethVault.address, ethxAmount);
    usbTotalSupply = await usb.totalSupply();
    // console.log(await ethVaultPtyPoolAboveAARU.totalStakingBalance());
    await expect(ethVault.connect(Alice).redeemByPairsWithExpectedLeveragedTokenAmount(ethxAmount))
      .to.emit(ethVault, 'YieldsSettlement').withArgs(anyValue, anyValue)
      .to.emit(ethVaultPtyPoolBelowAARS, 'StakingYieldsAdded').withArgs(anyValue)
      .to.emit(ethVaultPtyPoolAboveAARU, 'StakingYieldsAdded').withArgs(anyValue)
      .to.emit(ethVaultPtyPoolAboveAARU, 'MatchingYieldsAdded').withArgs(anyValue)
      .to.emit(ethVaultPtyPoolAboveAARU, 'MatchedTokensAdded').withArgs(anyValue);
    // console.log(await ethVaultPtyPoolAboveAARU.totalStakingBalance());
    await dumpVaultState(ethVault);
  });

});