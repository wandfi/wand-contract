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
    
    // Create ETH asset pool
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

    // Create PtyPools for $ETH vault
    const PtyPoolFactory = await ethers.getContractFactory('PtyPool');
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
    let expectedEthxAmount = ethers.utils.parseUnits('0.6667', await ethx.decimals());
    let expectedUsbAmount = ethers.utils.parseUnits('2666.666666666666666666', await usb.decimals());
    let calcOut = await vaultCalculator.calcMintPairsAtStabilityPhase(ethVault.address, ethDepositAmount);
    expectBigNumberEquals(calcOut[1], expectedUsbAmount);
    expectBigNumberEquals(calcOut[2], expectedEthxAmount);

    
  });

});