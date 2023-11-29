import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  maxContractSize, nativeTokenAddress, PtyPoolType,
  deployContractsFixture, dumpContracts, dumpVaultState, expectBigNumberEquals
} from './utils';
import { 
  Vault__factory,
  LeveragedToken__factory,
  PtyPool__factory
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Vaults', () => {

  it('Vault Management Works', async () => {

    const {
      Alice, Bob, Caro, ethPriceFeed, usb,
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
    console.log(`PtyPool code size: ${Vault.bytecode.length / 2} bytes`);
    expect(PtyPoolFactory.bytecode.length / 2).lessThan(maxContractSize);
    const EthVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(ethVault.address, PtyPoolType.RedeemByUsbBelowAARS, ethx.address, nativeTokenAddress);
    const ethVaultPtyPoolBelowAARS = PtyPool__factory.connect(EthVaultPtyPoolBelowAARS.address, provider);
    const EthVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(ethVault.address, PtyPoolType.MintUsbAboveAARU, nativeTokenAddress, ethx.address);
    const ethVaultPtyPoolAboveAARU = PtyPool__factory.connect(EthVaultPtyPoolAboveAARU.address, provider);
    let trans = await ethVault.connect(Alice).setPtyPools(ethVaultPtyPoolBelowAARS.address, ethVaultPtyPoolAboveAARU.address);
    await trans.wait();

    await dumpContracts(wandProtocol.address);

    // Initial AAR should be 0
    expect (await ethVault.AAR()).to.equal(0);

    // Set Y & C to 0 to facilitate testing
    await expect(ethVault.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("Y"), 0))
      .to.emit(ethVault, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("Y"), 0);
    await expect(ethVault.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("C"), 0))
      .to.emit(ethVault, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("C"), 0);

    /**
     * Asset Pool State: M_ETH = 0, M_USB = 0, M_ETHx = 0, P_ETH = $2000
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
    expectBigNumberEquals(calcOut[1], expectedUsbAmount);
    expectBigNumberEquals(calcOut[2], expectedEthxAmount);
    await expect(ethVault.connect(Alice).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Asset Pool State:
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
    expectBigNumberEquals(calcOut[1], expectedUsbAmount);
    expectBigNumberEquals(calcOut[2], expectedEthxAmount);
    await expect(ethVault.connect(Bob).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Bob, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Bob, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Bob, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Bob.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Bob.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Asset Pool State:
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
    expectBigNumberEquals(calcOut[1], expectedUsbAmount);
    expectBigNumberEquals(calcOut[2], expectedEthxAmount);
    await expect(ethVault.connect(Caro).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Caro, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Caro, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Caro, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Caro.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Caro.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Asset Pool State:
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
    expectBigNumberEquals(calcOut[1], expectedUsbAmount);
    expectBigNumberEquals(calcOut[2], expectedEthxAmount);
    await expect(ethVault.connect(Alice).mintPairsAtStabilityPhase(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, expectedEthxAmount)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethVault, 'LeveragedTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedEthxAmount, ethPrice, await ethPriceFeed.decimals());

    /**
     * Asset Pool State:
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
    expectBigNumberEquals(calcOut2[1], expectedUsbAmount);
    await expect(ethVault.connect(Alice).mintUSBAboveAARU(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice, ethVault], [ethDepositAmount.mul(-1), ethDepositAmount])
      .to.changeTokenBalance(usb, Alice, expectedUsbAmount)
      .to.changeTokenBalance(ethx, Alice, 0)
      .to.emit(ethVault, 'UsbMinted').withArgs(Alice.address, ethDepositAmount, expectedUsbAmount, anyValue, ethPrice, await ethPriceFeed.decimals());
   
    /**
     * Asset Pool State:
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
    expectBigNumberEquals(calcOut[1], expectedUsbAmount);
    expectBigNumberEquals(calcOut[2], expectedEthxAmount);
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
    expectBigNumberEquals(usbBlance, prevUsbBlance.add(expectedUsbAmount));
    expectBigNumberEquals(ethxBlance, prevEthxBlance.add(expectedEthxAmount));

    /**
     * Asset Pool State:
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
     * Set ETH price to $1000
     * Alice deposit 1 ETH to mint $USB and $ETHx
     * Expected out:
     *  ΔUSB = ΔETH * P_ETH * 1 / AAR = 1 * 3000 / 203.773585% = 1472.22222154
     *  ΔETHx = ΔETH * P_ETH * M_ETHx / (AAR * Musb-eth) = 1 * 3000 * 3.666666666666666665 / (203.773585% * 17666.666666666666666665) = 0.30555555541
     */
    await dumpVaultState(ethVault);
    ethPrice = ethers.utils.parseUnits('1000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpVaultState(ethVault);

    
  });

});