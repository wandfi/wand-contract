import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { deployContractsFixture, nativeTokenAddress, PtyPoolType, VaultPhase, ONE_DAY_IN_SECS } from './utils';

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

    const LeveragedTokenFactory = await ethers.getContractFactory('LeveragedToken');
    const ETHx = await LeveragedTokenFactory.deploy( 'ETHx Token', 'ETHx');
    const ethx = LeveragedToken__factory.connect(ETHx.address, provider);

    const MockVaultFactory = await ethers.getContractFactory('MockVault');
    const MockVault = await MockVaultFactory.deploy(nativeTokenAddress, usb.address, ethx.address);
    const vault = MockVault__factory.connect(MockVault.address, provider);

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

  it('PytPoolBelowAARS works', async () => {

    const { Alice, Bob, Caro } = await loadFixture(deployContractsFixture);
    const { usb, vault, ethx, ptyPoolBelowAARS } = await loadFixture(deployVaultsAndPtyPoolsFixture);

    /**
     * Mint 1000 $USB to Alice and Bob, and rebase to 4000
     * 
     * USB
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
     * USB
     *  Shares: total 2000, Alice 900, Bob 1000, PtyPoolBelowAARS 100
     *  Balance: total 4000, Alice 1800, Bob 2000, PtyPoolBelowAARS 200
     * PtyPoolBelowAARS
     *  LP Shares: total 200, Alice 200
     */
    await expect(usb.connect(Alice).approve(ptyPoolBelowAARS.address, ethers.utils.parseUnits('200', await usb.decimals()))).not.to.be.rejected;
    await expect(ptyPoolBelowAARS.connect(Alice).stake(ethers.utils.parseUnits('200', await usb.decimals())))
      .to.emit(usb, 'Transfer').withArgs(Alice.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('200', await usb.decimals()))
      .to.emit(usb, 'TransferShares').withArgs(Alice.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('100', await usb.decimals()))
      .to.emit(ptyPoolBelowAARS, 'Staked').withArgs(Alice.address, ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await usb.sharesOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await usb.balanceOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Alice.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Alice.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.totalStakingBalance()).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));

    /**
     * Vault add 100 $ETHx staking yields
     * 
     * Staking Yiels ($ETHx)
     *  Alice: 100 yields
     */
    await expect(vault.connect(Alice).mockAddStakingYieldsToPtyPoolBelowAARS(ethers.utils.parseUnits('100', await ethx.decimals())))
      .to.emit(ethx, 'Transfer').withArgs(vault.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('100', await ethx.decimals()))
      .to.emit(ptyPoolBelowAARS, 'StakingYieldsAdded').withArgs(ethers.utils.parseUnits('100', await ethx.decimals()));
    expect(await ptyPoolBelowAARS.earnedStakingYields(Alice.address)).to.equal(ethers.utils.parseUnits('100', await ethx.decimals()));

    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 1);

    /**
     * USB rebase from 4000 to 8000 ====> 
     * 
     * USB
     *  Shares: total 2000, Alice 900, Bob 1000, PtyPoolBelowAARS 100
     *  Balance: total 8000, Alice 3600, Bob 4000, PtyPoolBelowAARS 400
     * 
     * PtyPoolBelowAARS
     *  Total balance: 400
     *  LP Shares: total 200, Alice 200
     * 
     * -------------------------
     * 
     * Bob stakes 200 $USB to PtyPoolBelowAARS, and got 50 Pty LP  ===>
     * 
    *  USB
     *  Shares: total 2000, Alice 850, Bob 1000, PtyPoolBelowAARS 150
     *  Balance: total 8000, Alice 3400, Bob 4000, PtyPoolBelowAARS 600
     * 
     * PtyPoolBelowAARS
     *  Total balance: 400 + 200 = 600, Alice 400, Bob 200
     *  LP Shares: total 300, Alice 200, Bob 100
     */
    await expect(usb.connect(Alice).rebase(ethers.utils.parseUnits('4000', await usb.decimals()))).not.to.be.rejected;
    expect(await ptyPoolBelowAARS.totalStakingBalance()).to.equal(ethers.utils.parseUnits('400', await usb.decimals()));
    expect(await ptyPoolBelowAARS.totalStakingShares()).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    await expect(usb.connect(Bob).approve(ptyPoolBelowAARS.address, ethers.utils.parseUnits('200', await usb.decimals()))).not.to.be.rejected;
    await expect(ptyPoolBelowAARS.connect(Bob).stake(ethers.utils.parseUnits('200', await usb.decimals())))
      .to.emit(usb, 'Transfer').withArgs(Bob.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('200', await usb.decimals()))
      .to.emit(usb, 'TransferShares').withArgs(Bob.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('50', await usb.decimals()))
      .to.emit(ptyPoolBelowAARS, 'Staked').withArgs(Bob.address, ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await usb.sharesOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('150', await usb.decimals()));
    expect(await usb.balanceOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('600', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Bob.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Bob.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await ptyPoolBelowAARS.totalStakingBalance()).to.equal(ethers.utils.parseUnits('600', await usb.decimals()));
    expect(await ptyPoolBelowAARS.earnedStakingYields(Bob.address)).to.equal(ethers.utils.parseUnits('0', await ethx.decimals()));

    /**
     * Alice withdraw 200 $USB (50 shares) from PtyPoolBelowAARS  ====>
     * 
     * USB
     *  Shares: total 2000, Alice 850 -> 900, Bob 1000, PtyPoolBelowAARS 150 -> 100
     *  Balance: total 8000, Alice 3400 -> 3600, Bob 4000, PtyPoolBelowAARS 600 -> 400
     * 
     * PtyPoolBelowAARS
     *  Total balance: 600 -> 400, Alice 400 -> 200, Bob 200
     *  LP Shares: total 300 -> 200, Alice 200 -> 100, Bob 100
     */
    await expect(ptyPoolBelowAARS.connect(Alice).withdraw(ethers.utils.parseUnits('200', await usb.decimals())))
      .to.emit(usb, 'Transfer').withArgs(ptyPoolBelowAARS.address, Alice.address, ethers.utils.parseUnits('200', await usb.decimals()))
      .to.emit(usb, 'TransferShares').withArgs(ptyPoolBelowAARS.address, Alice.address, ethers.utils.parseUnits('50', await usb.decimals()))
      .to.emit(ptyPoolBelowAARS, 'Withdrawn').withArgs(Alice.address, ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await usb.sharesOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Alice.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Alice.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await ptyPoolBelowAARS.totalStakingBalance()).to.equal(ethers.utils.parseUnits('400', await usb.decimals()));

    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);

    /**
     * Vault add 20 $ETH matching yeilds
     * 
     * Staking Yiels ($ETHx)
     *  Alice: 100 yields
     * Matching Yields ($ETH) not distributed, so:
     *  Alice: 0, Bob: 0
     */
    await expect(vault.connect(Alice).mockAddMatchingYieldsToPtyPoolBelowAARS(ethers.utils.parseUnits('20'), {value: ethers.utils.parseUnits('20')}))
      .to.changeEtherBalances([Alice.address, ptyPoolBelowAARS.address], [ethers.utils.parseEther('-20'), ethers.utils.parseEther('20')])
      .to.emit(ptyPoolBelowAARS, 'MatchingYieldsAdded').withArgs(ethers.utils.parseUnits('20'));
    expect(await ptyPoolBelowAARS.earnedMatchingYields(Alice.address)).to.equal(ethers.utils.parseUnits('0'));
    expect(await ptyPoolBelowAARS.earnedMatchingYields(Bob.address)).to.equal(ethers.utils.parseUnits('0'));

    /**
     * Vault match 360 $USB (90 shares burned) to 36 $ETH
     * 
     * USB
     *  Shares: total 2000 - 90 = 1910, Alice 900, Bob 1000, PtyPoolBelowAARS 100 - 90 = 10
     *  Balance: total 8000 - 360 = 7640, Alice 3600, Bob 4000, PtyPoolBelowAARS 400 - 360 = 40
     * 
     * PtyPoolBelowAARS
     *  Total balance: 400 -> 40, Alice 200 -> 20, Bob 200 -> 20
     *  LP Shares: total 200, Alice 100, Bob 100
     * 
     * Staking Yiels ($ETHx)
     *  Alice: 100 yields
     * Matched Tokens ($ETH):
     *  Total: 36, Alice: 18, Bob: 18
     * Matching Yields ($ETH) also distributed, so:
     *  Alice: 10, Bob: 10
     */
    await expect(vault.connect(Alice).mockMatchedPtyPoolBelowAARS(ethers.utils.parseUnits('36'), ethers.utils.parseUnits('360'), {value: ethers.utils.parseUnits('36')})).to.be.rejectedWith('Vault not at adjustment below AARS phase');
    await expect(vault.connect(Alice).mockSetVaultPhase(VaultPhase.AdjustmentBelowAARS)).not.to.be.rejected;
    await expect(vault.connect(Alice).mockMatchedPtyPoolBelowAARS(ethers.utils.parseUnits('36'), ethers.utils.parseUnits('360'), {value: ethers.utils.parseUnits('36')}))
      .to.changeEtherBalances([Alice.address, ptyPoolBelowAARS.address], [ethers.utils.parseEther('-36'), ethers.utils.parseEther('36')])
      .to.changeTokenBalances(usb, [ptyPoolBelowAARS.address], [ethers.utils.parseUnits('-360', await usb.decimals())])
      .to.emit(ptyPoolBelowAARS, 'MatchedTokensAdded').withArgs(ethers.utils.parseUnits('36'));
    expect(await usb.sharesOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('10', await usb.decimals()));
    expect(await usb.balanceOf(ptyPoolBelowAARS.address)).to.equal(ethers.utils.parseUnits('40', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Alice.address)).to.equal(ethers.utils.parseUnits('20', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Alice.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Bob.address)).to.equal(ethers.utils.parseUnits('20', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Bob.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await ptyPoolBelowAARS.totalStakingBalance()).to.equal(ethers.utils.parseUnits('40', await usb.decimals()));
    expect(await ptyPoolBelowAARS.earnedMatchingYields(Alice.address)).to.equal(ethers.utils.parseUnits('10'));
    expect(await ptyPoolBelowAARS.earnedMatchingYields(Bob.address)).to.equal(ethers.utils.parseUnits('10'));
    expect(await ptyPoolBelowAARS.earnedMatchedToken(Alice.address)).to.equal(ethers.utils.parseUnits('18'));
    expect(await ptyPoolBelowAARS.earnedMatchedToken(Bob.address)).to.equal(ethers.utils.parseUnits('18'));

    /**
     * Alice claims matching yields and matched tokens
     * 
     * Matched Tokens ($ETH):
     *  Total: 36 - 18 = 0, Alice: 18 -> 0, Bob: 18
     * Matching Yields ($ETH) also distributed, so:
     *  Alice: 10 -> 0, Bob: 10
     */
    await expect(ptyPoolBelowAARS.connect(Alice).getMatchingTokensAndYields())
      .to.changeEtherBalances([Alice.address, ptyPoolBelowAARS.address], [ethers.utils.parseEther('28'), ethers.utils.parseEther('-28')])
      .to.emit(ptyPoolBelowAARS, 'MatchedTokenPaid').withArgs(Alice.address, ethers.utils.parseEther('18'))
      .to.emit(ptyPoolBelowAARS, 'MatchingYieldsPaid').withArgs(Alice.address, ethers.utils.parseEther('10'));
    expect(await ptyPoolBelowAARS.earnedMatchingYields(Alice.address)).to.equal(ethers.utils.parseUnits('0'));
    expect(await ptyPoolBelowAARS.earnedMatchedToken(Alice.address)).to.equal(ethers.utils.parseUnits('0'));

    /**
     * Bob transfer 200 $USB (50 shares) to Caro;
     * Caro stakes 40 $USB (10 shares) to PtyPoolBelowAARS, and got 50 Pty LP
     * 
     * USB
     *  Shares: total 1910, Alice 900, Bob 1000 - 50 = 950, Caro: 50, PtyPoolBelowAARS 10
     *  Balance: total 7640, Alice 3600, Bob 4000 - 200 = 3800, Caro: 200, PtyPoolBelowAARS 40
     * 
     * PtyPoolBelowAARS
     *  Total balance: 40 + 200 = 240, Alice 20, Bob 20, Caro 40
     *  LP Shares: total 200 + 200 = 400, Alice 100, Bob 100, Caro 200
     */
    await expect(usb.connect(Bob).transfer(Caro.address, ethers.utils.parseUnits('200', await usb.decimals())))
      .to.changeTokenBalances(usb, [Bob.address, Caro.address], [ethers.utils.parseUnits('-200', await usb.decimals()), ethers.utils.parseUnits('200', await usb.decimals())]);
    await expect(usb.connect(Caro).approve(ptyPoolBelowAARS.address, ethers.utils.parseUnits('40', await usb.decimals()))).not.to.be.rejected;
    await expect(ptyPoolBelowAARS.connect(Caro).stake(ethers.utils.parseUnits('40', await usb.decimals())))
      .to.changeTokenBalances(usb, [Caro.address, ptyPoolBelowAARS.address], [ethers.utils.parseUnits('-40', await usb.decimals()), ethers.utils.parseUnits('40', await usb.decimals())])
      .to.emit(usb, 'Transfer').withArgs(Caro.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('40', await usb.decimals()))
      .to.emit(usb, 'TransferShares').withArgs(Caro.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('10', await usb.decimals()))
      .to.emit(ptyPoolBelowAARS, 'Staked').withArgs(Caro.address, ethers.utils.parseUnits('40', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingShares(Caro.address)).to.equal(ethers.utils.parseUnits('200', await usb.decimals()));
    expect(await ptyPoolBelowAARS.userStakingBalance(Caro.address)).to.equal(ethers.utils.parseUnits('40', await usb.decimals()));

    /**
     * Vault add 40 $ETHx staking yields
     * 
     * PtyPoolBelowAARS
     *  Total balance: 240, Alice 20, Bob 20, Caro 40
     *  LP Shares: total 400, Alice 100, Bob 100, Caro 200
     * 
     * Staking Yiels ($ETHx)
     *  Alice: 100 + 10 = 110, Bob: 10, Caro: 20
     */
    await expect(vault.connect(Alice).mockAddStakingYieldsToPtyPoolBelowAARS(ethers.utils.parseUnits('40', await ethx.decimals())))
      .to.emit(ethx, 'Transfer').withArgs(vault.address, ptyPoolBelowAARS.address, ethers.utils.parseUnits('40', await ethx.decimals()))
      .to.emit(ptyPoolBelowAARS, 'StakingYieldsAdded').withArgs(ethers.utils.parseUnits('40', await ethx.decimals()));
    expect(await ptyPoolBelowAARS.earnedStakingYields(Alice.address)).to.equal(ethers.utils.parseUnits('110', await ethx.decimals()));
    expect(await ptyPoolBelowAARS.earnedStakingYields(Bob.address)).to.equal(ethers.utils.parseUnits('10', await ethx.decimals()));
    expect(await ptyPoolBelowAARS.earnedStakingYields(Caro.address)).to.equal(ethers.utils.parseUnits('20', await ethx.decimals()));
  
  });

});
