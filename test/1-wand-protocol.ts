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

describe('Wand Protocol', () => {

  it('Basic E2E Scenario Works', async () => {

    const {
      Alice, Bob, Caro, wbtc, ethPriceFeed, wbtcPriceFeed,
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
    const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(365).div(10000);  // 3.65%
    const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
    await expect(wandProtocol.connect(Alice).addAssetPool(ethAddress, ethPriceFeed.address, ethxToken.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
      [ethY, ethAART, ethAARS, ethAARC]))
      .to.emit(assetPoolFactory, 'AssetPoolAdded').withArgs(ethAddress, ethPriceFeed.address, anyValue);
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

    // Create $WBTC asset pool
    const WBTCx = await AssetXFactory.deploy(wandProtocol.address, "WBTCx Token", "WBTCx");
    const wbtcxToken = AssetX__factory.connect(WBTCx.address, provider);
    const wbtcY = BigNumber.from(10).pow(await settings.decimals()).mul(30).div(1000);  // 3%
    const wbtcAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const wbtcAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const wbtcAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
    await expect(wandProtocol.connect(Alice).addAssetPool(wbtc.address, wbtcPriceFeed.address, wbtcxToken.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
      [wbtcY, wbtcAART, wbtcAARS, wbtcAARC])
    ).to.emit(assetPoolFactory, 'AssetPoolAdded').withArgs(wbtc.address, wbtcPriceFeed.address, anyValue);

    await dumpContracts(wandProtocol.address);
    
    // Check $WBTCx is added as a reward token to $USB interest pool
    const wbtcxPoolAddress = await assetPoolFactory.getAssetPoolAddress(wbtc.address);
    const wbtcPool = AssetPool__factory.connect(wbtcxPoolAddress, provider);
    expect(await usbInterestPool.rewardTokenAdded(wbtcxToken.address)).to.be.true;

    // Day 1. Suppose ETH price is $2000. Alice deposit 2 ETH to mint 4000 $USB
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS);
    const ethPrice1 = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    const aliceDepositETH = ethers.utils.parseEther('2');
    const expectedUsbAmount = ethers.utils.parseUnits('4000', await usbToken.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice1)).not.to.be.reverted;
    expect(await ethPool.calculateMintUSBOut(aliceDepositETH)).to.equal(expectedUsbAmount);
    await expect(ethPool.connect(Alice).mintUSB(aliceDepositETH, {value: aliceDepositETH}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-2'), aliceDepositETH])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedUsbAmount)
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, aliceDepositETH, expectedUsbAmount, ethPrice1, await ethPriceFeed.decimals());
    expect(await usbToken.balanceOf(Alice.address)).to.equal(expectedUsbAmount);
    // await dumpAssetPoolState(ethPool);

    //  Day 2. ETH price is $3000. Bob deposit 1 ETH to mint 3000 $USB
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);
    const ethPrice2 = ethers.utils.parseUnits('3000', await ethPriceFeed.decimals());
    const bobDepositETH = ethers.utils.parseEther('1');
    const expectedUsbAmount2 = ethers.utils.parseUnits('3000', await usbToken.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice2)).not.to.be.reverted;
    // await dumpAssetPoolState(ethPool);
    expect(await ethPool.calculateMintUSBOut(bobDepositETH)).to.equal(expectedUsbAmount2);
    await expect(ethPool.connect(Bob).mintUSB(bobDepositETH, {value: bobDepositETH}))
      .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-1'), bobDepositETH])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, expectedUsbAmount2)
      .to.emit(ethPool, 'USBMinted').withArgs(Bob.address, bobDepositETH, expectedUsbAmount2, ethPrice2, await ethPriceFeed.decimals());
    
    // Day 3. ETH price is $3500. Caro deposit 4 ETH to mint 4 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 3);
    const ethPrice3 = ethers.utils.parseUnits('3500', await ethPriceFeed.decimals());
    const caroDepositETH = ethers.utils.parseEther('4');
    const expectedETHxAmount = ethers.utils.parseUnits('4', await ethxToken.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice3)).not.to.be.reverted;
    expect(await ethPool.calculateMintXTokensOut(caroDepositETH)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Caro).mintXTokens(caroDepositETH, {value: caroDepositETH}))
      .to.changeEtherBalances([Caro.address, ethPool.address], [ethers.utils.parseEther('-4'), caroDepositETH])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Caro.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Caro.address, caroDepositETH, expectedETHxAmount, ethPrice3, await ethPriceFeed.decimals());
    expectBigNumberEquals(await ethxToken.balanceOf(Caro.address), expectedETHxAmount);

    // Day 4. Bob deposit 1 ETH to mint $ETH
    // Current state: Meth = 4; Musb-eth = 7000;  APY = 3.65%; Peth = 3500; Methx = 4 + interest
    //  Interest generated: (1 day / 365) * 3.65% * 4 = ~0.0004 $ETHx
    //  Expected amount: (1 * $3500 * 4) / (7 * $3500 - 7000) = ~0.8
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 4);
    const expectedInterest = ethers.utils.parseUnits('0.0004', await ethxToken.decimals());
    expectBigNumberEquals((await ethPool.calculateInterest())[0], expectedInterest);
    const bobDepositETH2 = ethers.utils.parseEther('1');
    const expectedETHxAmount2 = ethers.utils.parseUnits('0.8', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(bobDepositETH2)).to.equal(expectedETHxAmount2);
    await expect(ethPool.connect(Bob).mintXTokens(bobDepositETH2, {value: bobDepositETH2}))
      .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-1'), bobDepositETH2])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, anyValue)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Bob.address, bobDepositETH2, anyValue, ethPrice3, await ethPriceFeed.decimals());
    // Interest is generated but not distributed, since no staking in the interest pool yet
    expectBigNumberEquals(await ethxToken.balanceOf(ethPool.address), expectedInterest);
    expectBigNumberEquals(await ethxToken.balanceOf(Bob.address), expectedETHxAmount2);

    // Day 5. Alice stakes 1000 $USB to earn interest; Bob stakes 2000 $USB to earn interest
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    const aliceStakeAmount = ethers.utils.parseUnits('1000', await usbToken.decimals());
    const bobStakeAmount = ethers.utils.parseUnits('2000', await usbToken.decimals());
    await expect(usbToken.connect(Alice).approve(usbInterestPool.address, aliceStakeAmount)).not.to.be.reverted;
    await expect(usbToken.connect(Bob).approve(usbInterestPool.address, bobStakeAmount)).not.to.be.reverted;
    await expect(usbInterestPool.connect(Alice).stake(aliceStakeAmount)).not.to.be.reverted;
    await expect(usbInterestPool.connect(Bob).stake(bobStakeAmount)).not.to.be.reverted;

    // Day 6. Two more days interest generated
    //  Additional interest generated: (2 day / 365) * 3.65% * (4 + 0.8) = ~0.00096 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 6);
    const expectedInterest2 = ethers.utils.parseUnits('0.00096', await ethxToken.decimals());
    const totalInterest = expectedInterest.add(expectedInterest2);
    expectBigNumberEquals((await ethPool.calculateInterest())[1], totalInterest);

    // Settle interest. Alice should get 1000 / (1000 + 2000) * (0.0004 + 0.00096) = ~0.00045333333 $ETHx, and Bob should get 0.00090666666 $ETHx
    await expect(ethPool.connect(Bob).settleInterest())
      .to.emit(usbInterestPool, 'StakingRewardsAdded').withArgs(ethxToken.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, true);
    expectBigNumberEquals(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address), ethers.utils.parseUnits('0.00045333333', await ethxToken.decimals()));
    expectBigNumberEquals(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address), ethers.utils.parseUnits('0.00090666666', await ethxToken.decimals()));
    await expect(usbInterestPool.connect(Alice).getStakingRewards(ethxToken.address))
      .to.emit(ethxToken, 'Transfer').withArgs(usbInterestPool.address, Alice.address, anyValue)
      .to.emit(usbInterestPool, 'StakingRewardsPaid').withArgs(ethxToken.address, Alice.address, anyValue);
    await expect(usbInterestPool.connect(Bob).getAllStakingRewards())
      .to.emit(ethxToken, 'Transfer').withArgs(usbInterestPool.address, Bob.address, anyValue)
      .to.emit(usbInterestPool, 'StakingRewardsPaid').withArgs(ethxToken.address, Bob.address, anyValue);
    expect(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address)).to.equal(0);
    expect(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address)).to.equal(0);

    // Day 7. ETH price becomes $4000. Alice redeems 100 $USB
    //  C1 = 0.1%
    //  Δeth = 100 * (1 - 0.1%) / 4000 = 0.024975 ETH
    //  Fee: 100 / 4000 * 0.1% = 0.000025 ETH
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 7);
    const ethPrice4 = ethers.utils.parseUnits('4000', await ethPriceFeed.decimals());
    const aliceRedeemAmount = ethers.utils.parseUnits('100', await usbToken.decimals());
    const expectedEthAmount = ethers.utils.parseEther('0.024975');
    const expectedFee = ethers.utils.parseEther('0.000025');
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice4)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).redeemByUSB(aliceRedeemAmount))
      .to.changeEtherBalances([Alice.address, ethPool.address], [expectedEthAmount.add(expectedFee), ethers.utils.parseEther('-0.025')])
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, aliceRedeemAmount)
      .to.emit(ethPool, 'AssetRedeemedWithUSB').withArgs(Alice.address, aliceRedeemAmount, expectedEthAmount, ethPrice4, await ethPriceFeed.decimals())
      .to.emit(ethPool, 'AssetRedeemedWithUSBFeeCollected').withArgs(Alice.address, Alice.address, aliceRedeemAmount, expectedFee, ethPrice4, await ethPriceFeed.decimals());

    // Day 8. Bob redeems 0.1 $ETHx
    //  Musb_eth = 7000 - 100 = 6900; Methx = 4 + 0.8 + (some interest) = ~4.80192
    //  C2 = 0.5%;  Meth = 7.975
    //  Expected paired $USB: 0.1 * 6900 / 4.80192 = ~143.692522991
    //  Δeth: 0.1 * 7.975 * (1 - 0.5%) / 4.80192 = ~0.16524900456
    //  Fee: 0.1 * 7.975 * 0.5% / 4.80192 = ~0.000830397
    // await dumpAssetPoolState(ethPool);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 8);
    const bobRedeemETHxAmount = ethers.utils.parseUnits('0.1', await ethxToken.decimals());
    const expectedPairedUSBAmount = ethers.utils.parseUnits('143.692522991', await usbToken.decimals());
    const expectedETHAmount2 = ethers.utils.parseEther('0.16524900456');
    const expectedFee2 = ethers.utils.parseEther('0.000830397');
    expectBigNumberEquals(await ethPool.calculatePairedUSBAmountToRedeemByXTokens(bobRedeemETHxAmount), expectedPairedUSBAmount);
    await expect(ethxToken.connect(Bob).approve(ethPool.address, bobRedeemETHxAmount)).not.to.be.reverted;
    await expect(usbToken.connect(Bob).approve(ethPool.address, expectedPairedUSBAmount.mul(11).div(10))).not.to.be.reverted;
    await expect(ethPool.connect(Bob).redeemByXTokens(bobRedeemETHxAmount))
      // .to.changeEtherBalances([Bob.address, ethPool.address], [expectedETHAmount2.add(expectedFee2), ethers.utils.parseEther('-0.16607940157')])
      .to.emit(ethxToken, 'Transfer').withArgs(Bob.address, ethers.constants.AddressZero, bobRedeemETHxAmount)
      .to.emit(usbToken, 'Transfer').withArgs(Bob.address, ethers.constants.AddressZero, anyValue)
      .to.emit(ethPool, 'AssetRedeemedWithXTokens').withArgs(Bob.address, bobRedeemETHxAmount, anyValue, anyValue, ethPrice4, await ethPriceFeed.decimals())
      .to.emit(ethPool, 'AssetRedeemedWithXTokensFeeCollected').withArgs(Bob.address, Alice.address, bobRedeemETHxAmount, anyValue, anyValue, anyValue, ethPrice4, await ethPriceFeed.decimals());

    // Day 9. Alice 100 $USB -> $ETHx
    // await dumpAssetPoolState(ethPool);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 9);
    const aliceUSBSwapAmount = ethers.utils.parseUnits('100', await usbToken.decimals());
    const calculatedETHxAmount = await ethPool.calculateUSBToXTokensOut(aliceUSBSwapAmount);
    await expect(usbToken.connect(Alice).approve(ethPool.address, aliceUSBSwapAmount)).not.to.be.reverted;
    // console.log(calculatedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(aliceUSBSwapAmount))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, aliceUSBSwapAmount)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, aliceUSBSwapAmount, anyValue, ethPrice4, await ethPriceFeed.decimals());

  });

});