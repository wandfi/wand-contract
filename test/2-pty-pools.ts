import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { deployContractsFixture, nativeTokenAddress, PtyPoolType } from './utils';

import { 
  MockUsb__factory,
  MockVault__factory,
  LeveragedToken__factory,
  PtyPool__factory
} from '../typechain';

const { provider } = ethers;

describe('PytPool', () => {

  async function deployVaultsAndPtyPoolsFixture() {

    const { Alice } = await loadFixture(deployContractsFixture);

    const MockUsbFactory = await ethers.getContractFactory('MockUsb');
    const MockUsb = await MockUsbFactory.deploy();
    const usb = MockUsb__factory.connect(MockUsb.address, provider);

    const MockVaultFactory = await ethers.getContractFactory('MockVault');
    const MockVault = await MockVaultFactory.deploy(nativeTokenAddress, usb.address);
    const vault = MockVault__factory.connect(MockVault.address, provider);

    const LeveragedTokenFactory = await ethers.getContractFactory('LeveragedToken');
    const ETHx = await LeveragedTokenFactory.deploy( 'ETHx Token', 'ETHx');
    const ethx = LeveragedToken__factory.connect(ETHx.address, provider);

    let trans = await ethx.connect(Alice).setVault(vault.address);
    await trans.wait();

    const PtyPoolFactory = await ethers.getContractFactory('PtyPool');
    const PtyPoolBelowAARS = await PtyPoolFactory.deploy(vault.address, PtyPoolType.RedeemByUsbBelowAARS, ethx.address, nativeTokenAddress);
    const ptyPoolBelowAARS = PtyPool__factory.connect(PtyPoolBelowAARS.address, provider);

    const PtyPoolAboveAARU = await PtyPoolFactory.deploy(vault.address, PtyPoolType.MintUsbAboveAARU, nativeTokenAddress, ethx.address);
    const ptyPoolAboveAARU = PtyPool__factory.connect(PtyPoolAboveAARU.address, provider);

    trans = await vault.connect(Alice).setPtyPools(ptyPoolBelowAARS.address, ptyPoolAboveAARU.address);
    await trans.wait();

    return { usb, vault, ethx, ptyPoolBelowAARS, ptyPoolAboveAARU };
  }

  it('PytPool works', async () => {

    const { Alice, Bob, Caro } = await loadFixture(deployContractsFixture);
    const { usb, vault, ethx, ptyPoolBelowAARS, ptyPoolAboveAARU } = await loadFixture(deployVaultsAndPtyPoolsFixture);

    /**
     * Mint 1000 $USB to Alice and Bob, and rebase to 4000
     * 
     * USB:
     *  Shares: total 2000, Alice 1000, Bob 1000
     *  Balance: total 4000, Alice 2000, Bob 2000
     */
    await expect(usb.connect(Alice).mint(Alice.address, ethers.utils.parseUnits('1000', await usb.decimals()))).not.to.be.rejected;
    await expect(usb.connect(Alice).mint(Bob.address, ethers.utils.parseUnits('1000', await usb.decimals()))).not.to.be.rejected;
    await expect(usb.connect(Alice).rebase(ethers.utils.parseUnits('2000', await usb.decimals()))).not.to.be.rejected;
    expect(await usb.balanceOf(Alice.address)).to.equal(ethers.utils.parseUnits('2000', await usb.decimals()));
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('2000', await usb.decimals()));

    // Day 0
    const genesisTime = await time.latest();

    /**
     * Alice stakes 200 $USB to PtyPoolBelowAARS, and got 200 Pty LP
     * 
     * USB:
     *  Shares: total 2000, Alice 900, Bob 1000, PtyPoolBelowAARS 100
     *  Balance: total 4000, Alice 1800, Bob 2000, PtyPoolBelowAARS 200
     * PtyPoolBelowAARS
     *  Shares: total 100, Alice 100
     */
    await expect(usb.connect(Bob).approve(ptyPoolBelowAARS.address, ethers.utils.parseUnits('200', await usb.decimals()))).not.to.be.rejected;
    await expect(ptyPoolBelowAARS.connect(Bob).stake(ethers.utils.parseUnits('200', await usb.decimals())))
      .to.emit(usb, 'Transfer').withArgs(Bob.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('200', await usb.decimals()))
      .to.emit(usb, 'TransferShares').withArgs(Bob.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('100', await usb.decimals()))
      .to.emit(ptyPoolBelowAARS, 'Staked').withArgs(Bob.address, ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Bob.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Bob.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.totalStakingBalance()).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));



  });

});
