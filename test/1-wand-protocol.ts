import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ONE_DAY_IN_SECS, maxContractSize, nativeTokenAddress, deployContractsFixture, dumpAssetPoolState, dumpContracts, expectBigNumberEquals } from './utils';
import { 
  Vault__factory,
  AssetX__factory,
  UsbInterestPool__factory
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Wand Protocol', () => {

  it('Basic E2E Scenario Works', async () => {

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
    const ethPool = Vault__factory.connect(ethPoolAddress, provider);

    // Deploy $USB InterestPool
    const UsbInterestPoolFactory = await ethers.getContractFactory('UsbInterestPool');
    expect(UsbInterestPoolFactory.bytecode.length / 2).lessThan(maxContractSize);
    const UsbInterestPool = await UsbInterestPoolFactory.deploy(wandProtocol.address, interestPoolFactory.address, usbToken.address, [ethxToken.address]);
    const usbInterestPool = UsbInterestPool__factory.connect(UsbInterestPool.address, provider);
    await expect(interestPoolFactory.connect(Bob).notifyInterestPoolAdded(usbToken.address, usbInterestPool.address)).to.be.rejectedWith(/Ownable: caller is not the owner/);
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
    await expect(wbtcxToken.connect(Alice).setAssetPool(wbtcxPoolAddress)).not.to.be.reverted;
    const wbtcPool = Vault__factory.connect(wbtcxPoolAddress, provider);
    expect(await usbInterestPool.rewardTokenAdded(wbtcxToken.address)).to.be.true;

    // Deposit some $WBTC to mint $WBTCx and $USB
    let wbtcPrice = ethers.utils.parseUnits('30000', await wbtcPriceFeed.decimals());
    let daveDepositWBTC = ethers.utils.parseUnits('1', await wbtc.decimals());
    await expect(wbtcPriceFeed.connect(Alice).mockPrice(wbtcPrice)).not.to.be.reverted;
    let expectedWBTCXAmount = ethers.utils.parseUnits('1', await wbtcxToken.decimals());
    await expect(wbtc.connect(Alice).mint(Dave.address, daveDepositWBTC.mul(2))).not.to.be.reverted;
    await expect(wbtc.connect(Dave).approve(wbtcPool.address, daveDepositWBTC.mul(2))).not.to.be.reverted;
    await expect(wbtcPool.connect(Dave).mintXTokens(daveDepositWBTC)).not.to.be.reverted;
    let expectedUsbAmount = ethers.utils.parseUnits('30000', await usbToken.decimals());
    expect(await wbtcPool.calculateMintUSBOut(daveDepositWBTC)).to.equal(expectedUsbAmount);
    await expect(wbtcPool.connect(Dave).mintUSB(daveDepositWBTC))
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Dave.address, expectedUsbAmount)
      .to.emit(wbtcPool, 'USBMinted').withArgs(Dave.address, daveDepositWBTC, expectedUsbAmount, wbtcPrice, await wbtcPriceFeed.decimals());
    expect(await usbToken.balanceOf(Dave.address)).to.equal(expectedUsbAmount);

    // Day 1. ETH price is $3500. Caro deposit 4 ETH to mint 4 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS);
    // initial mint must be $EThx
    let ethPrice = ethers.utils.parseUnits('3500', await ethPriceFeed.decimals());
    let depositETHAmount = ethers.utils.parseEther('4');
    let expectedETHxAmount = ethers.utils.parseUnits('4', await ethxToken.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpAssetPoolState(ethPool);
    await expect(ethPool.calculateMintUSBOut(depositETHAmount)).to.be.rejectedWith(/AAR Below Safe Threshold/);
    expect(await ethPool.calculateMintXTokensOut(depositETHAmount)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Caro).mintXTokens(depositETHAmount, {value: depositETHAmount}))
      .to.changeEtherBalances([Caro.address, ethPool.address], [ethers.utils.parseEther('-4'), depositETHAmount])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Caro.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Caro.address, depositETHAmount, expectedETHxAmount, ethPrice, await ethPriceFeed.decimals());
    expectBigNumberEquals(await ethxToken.balanceOf(Caro.address), expectedETHxAmount);

    // Day 3. Suppose ETH price is $2000. Alice deposit 2 ETH to mint 4000 $USB
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 3);
    ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    depositETHAmount = ethers.utils.parseEther('2');
    expectedUsbAmount = ethers.utils.parseUnits('4000', await usbToken.decimals());
    expect(await ethPool.calculateMintUSBOut(depositETHAmount)).to.equal(expectedUsbAmount);
    await expect(ethPool.connect(Alice).mintUSB(depositETHAmount, {value: depositETHAmount}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-2'), depositETHAmount])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedUsbAmount)
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, depositETHAmount, expectedUsbAmount, ethPrice, await ethPriceFeed.decimals());
    expect(await usbToken.balanceOf(Alice.address)).to.equal(expectedUsbAmount);
    // await dumpAssetPoolState(ethPool);

    //  ETH price is $6000. Bob deposit 0.1 ETH to mint 600 $USB
    ethPrice = ethers.utils.parseUnits('6000', await ethPriceFeed.decimals());
    const bobDepositETH = ethers.utils.parseEther('0.1');
    const expectedUsbAmount2 = ethers.utils.parseUnits('600', await usbToken.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpAssetPoolState(ethPool);
    expect(await ethPool.calculateMintUSBOut(bobDepositETH)).to.equal(expectedUsbAmount2);
    await expect(ethPool.connect(Bob).mintUSB(bobDepositETH, {value: bobDepositETH}))
      .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-0.1'), bobDepositETH])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, expectedUsbAmount2)
      .to.emit(ethPool, 'USBMinted').withArgs(Bob.address, bobDepositETH, expectedUsbAmount2, ethPrice, await ethPriceFeed.decimals());

    // Day 4. Bob deposit 1 ETH to mint $ETH
    // Current state: Meth = 6.1; Musb-eth = 4600.0;  APY = 3.65%; Peth = 3500; Methx = 4 + interest
    //  Interest generated: (1 day / 365) * 3.65% * 4 = ~0.0004 $ETHx
    //  Expected amount: (1 * $3500 * 4) / (6.1 * $3500 - 4600) = ~0.83582089552
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 4);
    ethPrice = ethers.utils.parseUnits('3500', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    const expectedInterest = ethers.utils.parseUnits('0.0004', await ethxToken.decimals());
    expectBigNumberEquals((await ethPool.calculateInterest())[0], expectedInterest);
    const bobDepositETH2 = ethers.utils.parseEther('1');
    const expectedETHxAmount2 = ethers.utils.parseUnits('0.83582089552', await ethxToken.decimals());
    await dumpAssetPoolState(ethPool);
    expectBigNumberEquals(await ethPool.calculateMintXTokensOut(bobDepositETH2), expectedETHxAmount2);
    await expect(ethPool.connect(Bob).mintXTokens(bobDepositETH2, {value: bobDepositETH2}))
      .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-1'), bobDepositETH2])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, ethPool.address, anyValue)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, anyValue)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Bob.address, bobDepositETH2, anyValue, ethPrice, await ethPriceFeed.decimals());
    // Interest is generated but not distributed, since no staking in the interest pool yet
    expectBigNumberEquals(await ethxToken.balanceOf(ethPool.address), expectedInterest);
    expectBigNumberEquals(await ethxToken.balanceOf(Bob.address), expectedETHxAmount2);

    // Day 5. Alice stakes 100 $USB to earn interest; Bob stakes 200 $USB to earn interest
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    const aliceStakeAmount = ethers.utils.parseUnits('100', await usbToken.decimals());
    const bobStakeAmount = ethers.utils.parseUnits('200', await usbToken.decimals());
    await expect(usbToken.connect(Alice).approve(usbInterestPool.address, aliceStakeAmount)).not.to.be.reverted;
    await expect(usbToken.connect(Bob).approve(usbInterestPool.address, bobStakeAmount)).not.to.be.reverted;
    await expect(usbInterestPool.connect(Alice).stake(aliceStakeAmount)).not.to.be.reverted;
    await expect(usbInterestPool.connect(Bob).stake(bobStakeAmount)).not.to.be.reverted;

    // Day 6. Two more days interest generated
    //  Additional interest generated: (2 day / 365) * 3.65% * (4 + 0.83582089552) = ~0.00096716417 $ETHx
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 6);
    await dumpAssetPoolState(ethPool);
    const expectedInterest2 = ethers.utils.parseUnits('0.00096716417', await ethxToken.decimals());
    const totalInterest = expectedInterest.add(expectedInterest2);
    expectBigNumberEquals((await ethPool.calculateInterest())[1], totalInterest);

    // Settle interest. Alice should get 100 / (100 + 200) * (0.0004 + 0.00096716417) = ~0.00045572139 $ETHx, and Bob should get 0.00091144278 $ETHx
    await expect(ethPool.connect(Bob).settleInterest())
      .to.emit(usbInterestPool, 'StakingRewardsAdded').withArgs(ethxToken.address, anyValue)
      .to.emit(ethPool, 'InterestSettlement').withArgs(anyValue, true);
    expectBigNumberEquals(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Alice.address), ethers.utils.parseUnits('0.00045572139', await ethxToken.decimals()));
    expectBigNumberEquals(await usbInterestPool.stakingRewardsEarned(ethxToken.address, Bob.address), ethers.utils.parseUnits('0.00091144278', await ethxToken.decimals()));
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
    await dumpAssetPoolState(ethPool);
    await expect(ethPool.connect(Alice).redeemByUSB(aliceRedeemAmount))
      .to.changeEtherBalances([Alice.address, Ivy.address, ethPool.address], [expectedEthAmount, expectedFee, ethers.utils.parseEther('-0.025')])
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, aliceRedeemAmount)
      .to.emit(ethPool, 'AssetRedeemedWithUSB').withArgs(Alice.address, aliceRedeemAmount, expectedEthAmount, ethPrice4, await ethPriceFeed.decimals())
      .to.emit(ethPool, 'AssetRedeemedWithUSBFeeCollected').withArgs(Alice.address, Ivy.address, aliceRedeemAmount, expectedFee, ethPrice4, await ethPriceFeed.decimals());

    // Day 8. Bob redeems 0.1 $ETHx
    //  Meth = 7.075, Musb_eth = 4600 - 100 = 4500; Methx = ~4.837755465681313425
    //  C2 = 0.5%
    //  Expected paired $USB: 0.1 * 4500 / 4.837755465681313425 = ~93.018343567
    //  Δeth: 0.1 * 7.075 * (1 - 0.5%) / 4.837755465681313425 = ~0.14551427929
    //  Fee: 0.1 * 7.075 * 0.5% / 4.837755465681313425 = ~0.00073122753
    await dumpAssetPoolState(ethPool);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 8);
    const bobRedeemETHxAmount = ethers.utils.parseUnits('0.1', await ethxToken.decimals());
    const expectedPairedUSBAmount = ethers.utils.parseUnits('93.018343567', await usbToken.decimals());
    const expectedETHAmount2 = ethers.utils.parseEther('0.14551427929');
    const expectedFee2 = ethers.utils.parseEther('0.00073122753');
    expectBigNumberEquals(await ethPool.calculatePairedUSBAmountToRedeemByXTokens(bobRedeemETHxAmount), expectedPairedUSBAmount);
    await expect(ethxToken.connect(Bob).approve(ethPool.address, bobRedeemETHxAmount)).not.to.be.reverted;
    await expect(usbToken.connect(Bob).approve(ethPool.address, expectedPairedUSBAmount.mul(11).div(10))).not.to.be.reverted;
    await expect(ethPool.connect(Bob).redeemByXTokens(bobRedeemETHxAmount))
      // .to.changeEtherBalances([Bob.address, ethPool.address], [expectedETHAmount2.add(expectedFee2), ethers.utils.parseEther('-0.16607940157')])
      .to.emit(ethxToken, 'Transfer').withArgs(Bob.address, ethers.constants.AddressZero, bobRedeemETHxAmount)
      .to.emit(usbToken, 'Transfer').withArgs(Bob.address, ethers.constants.AddressZero, anyValue)
      .to.emit(ethPool, 'AssetRedeemedWithXTokens').withArgs(Bob.address, bobRedeemETHxAmount, anyValue, anyValue, ethPrice4, await ethPriceFeed.decimals())
      .to.emit(ethPool, 'AssetRedeemedWithXTokensFeeCollected').withArgs(Bob.address, Ivy.address, bobRedeemETHxAmount, anyValue, anyValue, anyValue, ethPrice4, await ethPriceFeed.decimals());

    // Day 9. Alice 100 $USB -> $ETHx
    await dumpAssetPoolState(ethPool);
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

  it('Could not Send Ethers to Wand Contracts', async () => {

    const {
      Alice, Bob, ethPriceFeed,
      wandProtocol, settings, usbToken, assetPoolFactory, interestPoolFactory
    } = await loadFixture(deployContractsFixture);

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
    const ethPool = Vault__factory.connect(ethPoolAddress, provider);

    // Deploy $USB InterestPool
    const UsbInterestPoolFactory = await ethers.getContractFactory('UsbInterestPool');
    expect(UsbInterestPoolFactory.bytecode.length / 2).lessThan(maxContractSize);
    const UsbInterestPool = await UsbInterestPoolFactory.deploy(wandProtocol.address, interestPoolFactory.address, usbToken.address, [ethxToken.address]);
    const usbInterestPool = UsbInterestPool__factory.connect(UsbInterestPool.address, provider);
    await expect(interestPoolFactory.connect(Bob).notifyInterestPoolAdded(usbToken.address, usbInterestPool.address)).to.be.rejectedWith(/Ownable: caller is not the owner/);
    await expect(interestPoolFactory.connect(Alice).notifyInterestPoolAdded(usbToken.address, usbInterestPool.address))
      .to.emit(interestPoolFactory, 'InterestPoolAdded').withArgs(usbToken.address, usbInterestPool.address);

    await expect (Alice.sendTransaction({to: wandProtocol.address, value: ethers.utils.parseEther('1')})).to.be.rejectedWith(/there's no fallback nor receive function/);
    await expect (Alice.sendTransaction({to: ethPool.address, value: ethers.utils.parseEther('1')})).to.be.rejectedWith(/there's no fallback nor receive function/);
    await expect (Alice.sendTransaction({to: usbInterestPool.address, value: ethers.utils.parseEther('1')})).to.be.rejectedWith(/there's no fallback nor receive function/);
    await expect (Alice.sendTransaction({to: usbToken.address, value: ethers.utils.parseEther('1')})).to.be.rejectedWith(/there's no fallback nor receive function/);
    await expect (Alice.sendTransaction({to: ethxToken.address, value: ethers.utils.parseEther('1')})).to.be.rejectedWith(/there's no fallback nor receive function/);

  });
});