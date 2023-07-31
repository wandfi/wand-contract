import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ONE_DAY_IN_SECS, maxContractSize, nativeTokenAddress, deployContractsFixture, dumpAssetPoolState, dumpContracts, expectBigNumberEquals } from './utils';
import { 
  AssetPool__factory,
  AssetX__factory,
  UsbInterestPool__factory
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Interest Pool', () => {

  it('$USB Interest Pool with $ETHx Rewards Works', async () => {

    const {
      Alice, Bob, Caro, Dave, Ivy, wbtc, ethPriceFeed, wbtcPriceFeed,
      wandProtocol, settings, usbToken, assetPoolFactory, interestPoolFactory
    } = await loadFixture(deployContractsFixture);

    // Day 0
    const genesisTime = await time.latest();

    // Create $ETHx token
    const AssetXFactory = await ethers.getContractFactory('AssetX');
    expect(AssetXFactory.bytecode.length / 2).lessThan(maxContractSize);
    const ETHx = await AssetXFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
    const ethxToken = AssetX__factory.connect(ETHx.address, provider);
    
    // Create ETH asset pool
    const ethAddress = nativeTokenAddress;
    await expect(wandProtocol.connect(Alice).addAssetPool(ethAddress, ethPriceFeed.address, ethxToken.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC"), ethers.utils.formatBytes32String("C1"), ethers.utils.formatBytes32String("C2")],
      [
        BigNumber.from(10).pow(await settings.decimals()).mul(365).div(10000), BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100),
        BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100), BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100),
        0, 0
      ])
    ).not.to.be.reverted;
    const ethPoolAddress = await assetPoolFactory.getAssetPoolAddress(ethAddress);
    await expect(ethxToken.connect(Alice).setAssetPool(ethPoolAddress)).not.to.be.reverted;
    const ethPool = AssetPool__factory.connect(ethPoolAddress, provider);

    // Deploy $USB InterestPool
    const UsbInterestPoolFactory = await ethers.getContractFactory('UsbInterestPool');
    expect(UsbInterestPoolFactory.bytecode.length / 2).lessThan(maxContractSize);
    const UsbInterestPool = await UsbInterestPoolFactory.deploy(wandProtocol.address, interestPoolFactory.address, usbToken.address, [ethxToken.address]);
    const usbInterestPool = UsbInterestPool__factory.connect(UsbInterestPool.address, provider);
    await expect(interestPoolFactory.connect(Alice).notifyInterestPoolAdded(usbToken.address, usbInterestPool.address))
      .to.emit(interestPoolFactory, 'InterestPoolAdded').withArgs(usbToken.address, usbInterestPool.address);
    console.log(`UsbInterestPool code size: ${UsbInterestPoolFactory.bytecode.length / 2} bytes`);
    
    // Add $USB InterestPool to $ETHx's whitelist
    await expect(ethxToken.connect(Alice).setWhitelistAddress(usbInterestPool.address, true))
      .to.emit(ethxToken, 'UpdateWhitelistAddress').withArgs(usbInterestPool.address, true);

    // Day 1. Set ETH price to $2000, Alice deposit 100 ETH to mint 100 $ETHx, and 1 ETH to mint 2000 $USB
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS);
    let ethPrice = BigNumber.from(2000).mul(BigNumber.from(10).pow(await ethPriceFeed.decimals()));
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).mintXTokens(ethers.utils.parseEther("100"), {value: ethers.utils.parseEther("100")})).not.to.be.rejected;
    await expect(ethPool.connect(Alice).mintUSB(ethers.utils.parseEther("1"), {value: ethers.utils.parseEther("1")})).not.to.be.rejected;
    await dumpAssetPoolState(ethPool);

    // Day 2. No interest distributed, since no $USB staking yet
    // ETH Pool State: M_ETH = 101, M_USB = 2000, M_USB_ETH = 2000, M_ETHx = 100
    // Expected interest:
    //  New interest: (1 day / 365 days) * 3.65% * 100 = 0.01 $ETHx
    //  Total interest: 0.01 $ETHx 
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);
    let expectedNewInterest = ethers.utils.parseUnits("0.01", await ethxToken.decimals());
    let expectedTotalInterest = ethers.utils.parseUnits("0.01", await ethxToken.decimals());
    let interestInfo = await ethPool.calculateInterest();
    expectBigNumberEquals(expectedNewInterest, interestInfo[0]);
    expectBigNumberEquals(expectedTotalInterest, interestInfo[1]);
    await expect(ethPool.connect(Alice).settleInterest())
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, false);
    await dumpAssetPoolState(ethPool);

    // Day 3. New interest generated, but still not distributed
    // ETH Pool State: M_ETHx = 100.009999768518518518
    // Expected interest:
    //  New interest: (1 day / 365 days) * 3.65% * 100.009999768518518518 = 0.01000099997 $ETHx
    //  Total interest: 0.02000099997 $ETHx 
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 3);
    expectedNewInterest = ethers.utils.parseUnits("0.01000099997", await ethxToken.decimals());
    expectedTotalInterest = ethers.utils.parseUnits("0.02000099997", await ethxToken.decimals());
    interestInfo = await ethPool.calculateInterest();
    expectBigNumberEquals(expectedNewInterest, interestInfo[0]);
    expectBigNumberEquals(expectedTotalInterest, interestInfo[1]);
    await expect(ethPool.connect(Bob).settleInterest())
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, false);
    await dumpAssetPoolState(ethPool);

    // Day 4. Alice stake 100 $USB, and get all the interest
    // ETH Pool State: M_ETHx = 100.020000768495370369
    // Expected interest:
    //  New interest: (1 day / 365 days) * 3.65% * 100.020000768495370369 = 0.01000200007 $ETHx
    //  Total interest: 0.03000300004 $ETHx
    let aliceStakeAmount = ethers.utils.parseUnits('100', await usbToken.decimals());
    await expect(usbToken.connect(Alice).approve(usbInterestPool.address, aliceStakeAmount)).not.to.be.reverted;
    await expect(usbInterestPool.connect(Alice).stake(aliceStakeAmount))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, usbInterestPool.address, aliceStakeAmount)
      .to.emit(usbInterestPool, 'Staked').withArgs(Alice.address, aliceStakeAmount);

    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 4);
    expectedNewInterest = ethers.utils.parseUnits("0.01000200007", await ethxToken.decimals());
    expectedTotalInterest = ethers.utils.parseUnits("0.03000300004", await ethxToken.decimals());
    interestInfo = await ethPool.calculateInterest();
    expectBigNumberEquals(expectedNewInterest, interestInfo[0]);
    expectBigNumberEquals(expectedTotalInterest, interestInfo[1]);

    await expect(ethPool.connect(Alice).settleInterest())
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, true);
    await dumpAssetPoolState(ethPool);

    expectBigNumberEquals(expectedTotalInterest, await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address));
    expect(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address)).to.equal(0);
    await expect(usbInterestPool.connect(Alice).stakingRewardsEarned(usbToken.address, Alice.address)).to.be.revertedWith(/Invalid reward token/)

    // Day 5. Bob stakes 50 $USB right before interest settlement, and get 1/3 of the new interest
    // ETH Pool State: M_ETHx = 100.030002768572219906
    // Expected interest:
    //  New interest: (1 day / 365 days) * 3.65% * 100.030002768572219906 = 0.01000300027 $ETHx
    //  Total interest: 0 + 0.01000300027 = 0.01000300027 $ETHx
    //  Alice total earned: 0.03000300004 + 0.01000300027 * 100 / 150 = 0.03667166688
    //  Bob total earned: 0.01000300027 * 50 / 150 = 0.00333433342
    await expect(usbToken.connect(Alice).transfer(Bob.address, ethers.utils.parseUnits('50', await usbToken.decimals()))).not.to.be.reverted;
    let bobStakeAmount = ethers.utils.parseUnits('50', await usbToken.decimals());
    await expect(usbToken.connect(Bob).approve(usbInterestPool.address, bobStakeAmount)).not.to.be.reverted;
    await expect(usbInterestPool.connect(Bob).stake(bobStakeAmount))
      .to.emit(usbToken, 'Transfer').withArgs(Bob.address, usbInterestPool.address, bobStakeAmount)
      .to.emit(usbInterestPool, 'Staked').withArgs(Bob.address, bobStakeAmount);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    expectedNewInterest = ethers.utils.parseUnits("0.01000300027", await ethxToken.decimals());
    expectedTotalInterest = ethers.utils.parseUnits("0.01000300027", await ethxToken.decimals());
    interestInfo = await ethPool.calculateInterest();
    expectBigNumberEquals(expectedNewInterest, interestInfo[0]);
    expectBigNumberEquals(expectedTotalInterest, interestInfo[1]);

    await expect(ethPool.connect(Alice).settleInterest())
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethxToken, 'Transfer').withArgs(ethPool.address, usbInterestPool.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, true);
    await dumpAssetPoolState(ethPool);

    expectBigNumberEquals(ethers.utils.parseUnits('0.03667166688', await ethxToken.decimals()), await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address));
    expectBigNumberEquals(ethers.utils.parseUnits('0.00333433342', await ethxToken.decimals()), await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address));

    // Alice unstakes 50 $USB
    let aliceUnstakeAmount = ethers.utils.parseUnits('50', await usbToken.decimals());
    await expect(usbInterestPool.connect(Alice).unstake(aliceUnstakeAmount))
      .to.emit(usbToken, 'Transfer').withArgs(usbInterestPool.address, Alice.address, aliceUnstakeAmount)
      .to.emit(usbInterestPool, 'Unstaked').withArgs(Alice.address, aliceUnstakeAmount);
    expect(await usbInterestPool.userStakingAmount(Alice.address)).to.equal(aliceStakeAmount.sub(aliceUnstakeAmount));

    // Get rewards
    let aliceRewardsAmount = await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address);
    await expect(usbInterestPool.connect(Alice).getStakingRewards(ethxToken.address))
      .to.emit(ethxToken, 'Transfer').withArgs(usbInterestPool.address, Alice.address, aliceRewardsAmount)
      .to.emit(usbInterestPool, 'StakingRewardsPaid').withArgs(ethxToken.address, Alice.address, aliceRewardsAmount);
    expect(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address)).to.equal(0);

    // Day 6. Both Alice and Bob have 50 $USB staking, each should get 1/2 of the new interest
    // ETH Pool State: M_ETHx = 100.040005768849077127
    // Expected interest:
    //  New interest: (1 day / 365 days) * 3.65% * 100.040005768849077127 = 0.01000400057 $ETHx
    //  Total interest: 0 + 0.01000400057 = 0.01000400057 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 6);
    expectedNewInterest = ethers.utils.parseUnits("0.01000400057", await ethxToken.decimals());
    expectedTotalInterest = ethers.utils.parseUnits("0.01000400057", await ethxToken.decimals());
    interestInfo = await ethPool.calculateInterest();
    expectBigNumberEquals(expectedNewInterest, interestInfo[0]);
    expectBigNumberEquals(expectedTotalInterest, interestInfo[1]);

    await expect(ethPool.connect(Alice).settleInterest())
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethxToken, 'Transfer').withArgs(ethPool.address, usbInterestPool.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, true);
    await dumpAssetPoolState(ethPool);

    let expectedBobRewards = ethers.utils.parseUnits('0.00333433342', await ethxToken.decimals()).add(expectedNewInterest.div(2));
    expectBigNumberEquals(expectedNewInterest.div(2), await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address));
    expectBigNumberEquals(expectedBobRewards, await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address));

    // getAllStakingRewards works
    let bobRewardsAmount = await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address);
    await expect(usbInterestPool.connect(Bob).getAllStakingRewards())
      .to.emit(ethxToken, 'Transfer').withArgs(usbInterestPool.address, Bob.address, bobRewardsAmount)
      .to.emit(usbInterestPool, 'StakingRewardsPaid').withArgs(ethxToken.address, Bob.address, bobRewardsAmount);
    expect(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address)).to.equal(0);

    // Alice and Bob unstakes all
    await expect(usbInterestPool.connect(Alice).unstake(await usbInterestPool.userStakingAmount(Alice.address))).not.to.be.reverted;
    await expect(usbInterestPool.connect(Bob).unstake(await usbInterestPool.userStakingAmount(Bob.address))).not.to.be.reverted;

    // Day 8. New interests generated, but not distributed
    // ETH Pool State: M_ETHx = 100.050009769425962034
    // Expected interest:
    //  New interest: (2 days / 365 days) * 3.65% * 100.050009769425962034 = 0.02001000195 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 8);
    expectedNewInterest = ethers.utils.parseUnits("0.02001000195", await ethxToken.decimals());
    await expect(ethPool.connect(Alice).settleInterest()).not.to.be.reverted;

    // 10 more days. New interests generated, but still not distributed
    // ETH Pool State: M_ETHx = 100.050009769425962034 + 0.02001000195 = 100.070019771375962034
    // Expected interest:
    //  New interest: (10 days / 365 days) * 3.65% * 100.070019771375962034 = 0.10007001977 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 18);
    expectedNewInterest = ethers.utils.parseUnits("0.10007001977", await ethxToken.decimals());
    expectedTotalInterest = expectedNewInterest.add(ethers.utils.parseUnits("0.02001000195", await ethxToken.decimals()));
    interestInfo = await ethPool.calculateInterest();
    expectBigNumberEquals(expectedNewInterest, interestInfo[0]);
    expectBigNumberEquals(expectedTotalInterest, interestInfo[1]);

  });

});