import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ONE_DAY_IN_SECS, deployContractsFixture, expectBigNumberEquals } from './utils';
import {
  ERC20Mock__factory,
  ProtoInterestPool__factory,
} from '../typechain';

const { provider } = ethers;

describe('Proto Interest Pool', () => {

  it('Proto Interest Pool Works', async () => {

    const { Alice, Bob, Caro } = await loadFixture(deployContractsFixture);

    const ERC20MockFactory = await ethers.getContractFactory('ERC20Mock');
    const USB = await ERC20MockFactory.deploy("USB Token", "USB");
    const usb = ERC20Mock__factory.connect(USB.address, provider);

    const ETHx = await ERC20MockFactory.deploy("ETHx Token", "ETHx");
    const ethx = ERC20Mock__factory.connect(ETHx.address, provider);

    const ProtoInterestPool = await ethers.getContractFactory('ProtoInterestPool');
    const ProtoInterestPoolContract = await ProtoInterestPool.deploy(ethx.address, usb.address);
    const protoInterestPool = ProtoInterestPool__factory.connect(ProtoInterestPoolContract.address, provider);

    const genesisTime = (await time.latest()) + ONE_DAY_IN_SECS;
    await expect(usb.connect(Alice).mint(Bob.address, ethers.utils.parseUnits('10000', await usb.decimals()))).not.to.be.reverted;
    await expect(usb.connect(Alice).mint(Caro.address, ethers.utils.parseUnits('10000'))).not.to.be.reverted;

    let totalReward = ethers.utils.parseUnits('10000');
    await expect(ethx.connect(Alice).mint(Alice.address, totalReward)).not.to.be.reverted;
    await expect(ethx.connect(Alice).approve(protoInterestPool.address, totalReward)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Alice).addRewards(totalReward))
      .to.emit(protoInterestPool, 'RewardAdded').withArgs(totalReward);
    

    // Bob stakes 800 $USB, and Caro stakes 200 $USB
    let bobStakeAmount = ethers.utils.parseUnits('800');
    let caroStakeAmount = ethers.utils.parseUnits('200');
    await expect(usb.connect(Bob).approve(protoInterestPool.address, bobStakeAmount)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Bob).stake(bobStakeAmount)).not.to.be.reverted;
    await expect(usb.connect(Caro).approve(protoInterestPool.address, caroStakeAmount)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Caro).stake(caroStakeAmount)).not.to.be.reverted;
    expect(await protoInterestPool.totalSupply()).to.equal(bobStakeAmount.add(caroStakeAmount));

    // Deposit 10000 $USB as reward
    await time.increaseTo(genesisTime);
    totalReward = ethers.utils.parseUnits('10000');
    await expect(ethx.connect(Alice).mint(Alice.address, totalReward)).not.to.be.reverted;
    await expect(ethx.connect(Alice).approve(protoInterestPool.address, totalReward)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Alice).addRewards(totalReward))
      .to.emit(protoInterestPool, 'RewardAdded').withArgs(totalReward);

    // Bob should immediately get 4/5 rewards, and Caro should get 1/5 rewards
    expectBigNumberEquals(totalReward.mul(4).div(5), await protoInterestPool.earned(Bob.address));
    expectBigNumberEquals(totalReward.mul(1).div(5), await protoInterestPool.earned(Caro.address));

    // Bob claim rewards
    // console.log('Bob earned', ethers.utils.formatUnits((await protoInterestPool.earned(Bob.address)).toString(), 18));
    await expect(protoInterestPool.connect(Bob).getReward())
      .to.emit(protoInterestPool, 'RewardPaid').withArgs(Bob.address, anyValue);
    
    // Add another round of reward
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    const round2Reward = ethers.utils.parseUnits('20000');
    await expect(ethx.connect(Alice).mint(Alice.address, round2Reward)).not.to.be.reverted;
    await expect(ethx.connect(Alice).approve(protoInterestPool.address, round2Reward)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Alice).addRewards(round2Reward))
      .to.emit(protoInterestPool, 'RewardAdded').withArgs(round2Reward);

    // Bob should get 4/5 rewards, and Caro should get 1/5 rewards
    expectBigNumberEquals(round2Reward.mul(4).div(5), await protoInterestPool.earned(Bob.address));
    expectBigNumberEquals(totalReward.mul(1).div(5).add(round2Reward.mul(1).div(5)), await protoInterestPool.earned(Caro.address));

    // Bob withdraw 600 stakes. Going forward, Bob and Caro should get 1/2 rewards respectively
    await expect(protoInterestPool.connect(Bob).withdraw(ethers.utils.parseUnits('600'))).not.to.be.reverted;

    // Fast-forward to Day 9. Add new reward
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 9);
    const round3Reward = ethers.utils.parseUnits('30000');
    await expect(ethx.connect(Alice).mint(Alice.address, round3Reward)).not.to.be.reverted;
    await expect(ethx.connect(Alice).approve(protoInterestPool.address, round3Reward)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Alice).addRewards(round3Reward)).not.to.be.reverted;

    // Fast-forward to Day 10. Add new reward
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 10);
    const round4Reward = ethers.utils.parseUnits('33333');
    await expect(ethx.connect(Alice).mint(Alice.address, round4Reward)).not.to.be.reverted;
    await expect(ethx.connect(Alice).approve(protoInterestPool.address, round4Reward)).not.to.be.reverted;
    await expect(protoInterestPool.connect(Alice).addRewards(round4Reward)).not.to.be.reverted;

    // Check Bob and Caro's rewards
    expectBigNumberEquals(round2Reward.mul(4).div(5).add(round3Reward.mul(1).div(2).add(round4Reward.mul(1).div(2))), await protoInterestPool.earned(Bob.address));
    expectBigNumberEquals(totalReward.mul(1).div(5).add(round2Reward.mul(1).div(5)).add(round3Reward.mul(1).div(2).add(round4Reward.mul(1).div(2))), await protoInterestPool.earned(Caro.address));

  });

});