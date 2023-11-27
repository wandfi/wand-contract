import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import {
  maxContractSize, nativeTokenAddress,
  PtyPoolType,
  deployContractsFixture, dumpContracts
} from './utils';
import { 
  LeveragedToken__factory,
  PtyPool__factory
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Wand Protocol', () => {

  it('Vault Management Works', async () => {

    const {
      Alice, wbtc, ethPriceFeed, wbtcPriceFeed,
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

    // Create PtyPools for $WBTC vault
    const WBTCVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(wbtcVault.address, PtyPoolType.RedeemByUsbBelowAARS, wbtcx.address, wbtc.address);
    const wbtcVaultPtyPoolBelowAARS = PtyPool__factory.connect(WBTCVaultPtyPoolBelowAARS.address, provider);
    const WBTCVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(wbtcVault.address, PtyPoolType.MintUsbAboveAARU, wbtc.address, wbtcx.address);
    const wbtcVaultPtyPoolAboveAARU = PtyPool__factory.connect(WBTCVaultPtyPoolAboveAARU.address, provider);
    trans = await wbtcVault.connect(Alice).setPtyPools(wbtcVaultPtyPoolBelowAARS.address, wbtcVaultPtyPoolAboveAARU.address);
    await trans.wait();

    await dumpContracts(wandProtocol.address);
    
  });

});