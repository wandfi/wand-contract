import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { nativeTokenAddress, maxContractSize, deployContractsFixture, dumpAssetPoolState, expectBigNumberEquals } from './utils';
import { 
  AssetPool__factory,
  AssetX__factory,
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Asset Pool', () => {

  it('Mint & Redemption (Without Interest & Fees) Works', async () => {

    const {
      Alice, Bob, Caro, Ivy, ethPriceFeed, wandProtocol, settings, usbToken, assetPoolFactory
    } = await loadFixture(deployContractsFixture);

    // Create $ETHx token
    const AssetXFactory = await ethers.getContractFactory('AssetX');
    expect(AssetXFactory.bytecode.length / 2).lessThan(maxContractSize);
    const ETHx = await AssetXFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
    const ethxToken = AssetX__factory.connect(ETHx.address, provider);
    
    // Create ETH asset pool
    const ethAddress = nativeTokenAddress;
    const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(0).div(10000);  // 0%
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

    // Initial AAR should be 0
    expect (await ethPool.AAR()).to.equal(0);

    // Set C1 & C2 to 0 to faciliate testing
    await expect(ethPool.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("C1"), 0))
      .to.emit(ethPool, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("C1"), 0);
    await expect(ethPool.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("C2"), 0))
      .to.emit(ethPool, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("C2"), 0);

    // Asset Pool State: M_ETH = 0, M_USB = 0, M_ETHx = 0, P_ETH = $2000
    // Alice deposit 2 ETH to mint 2 $ETHx
    let ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;

    let ethDepositAmount = ethers.utils.parseEther('2');
    let expectedETHxAmount = ethers.utils.parseUnits('2', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(ethDepositAmount)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Alice).mintXTokens(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-2'), ethDepositAmount])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedETHxAmount, ethPrice, await ethPriceFeed.decimals());
    
    // Asset Pool State: M_ETH = 2, M_USB = 0, M_ETHx = 2, P_ETH = $3000
    // Alice deposit 1 ETH to mint $USB, expected output is: 1 * 3000 = 3000
    await dumpAssetPoolState(ethPool);
    ethPrice = ethers.utils.parseUnits('3000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('1');
    const expectedUSBAmount = ethers.utils.parseUnits('3000', await usbToken.decimals());
    expect(await ethPool.calculateMintUSBOut(ethDepositAmount)).to.equal(expectedUSBAmount);
    await expect(ethPool.connect(Alice).mintUSB(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-1'), ethDepositAmount])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedUSBAmount)
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, ethDepositAmount, expectedUSBAmount, ethPrice, await ethPriceFeed.decimals());
    
    // Asset Pool State: M_ETH = 3, M_USB = 3000, M_ETHx = 2, AAR: 3 * 3000 / 3000 = 300%
    // await dumpAssetPoolState(ethPool);
    expect(await ethPool.AAR()).to.equal(ethers.utils.parseUnits('3', await ethPool.AARDecimals()));
    expect(await ethPool.getAssetTotalAmount()).to.equal(ethers.utils.parseEther('3'));
    expect(await ethPool.usbTotalSupply()).to.equal(ethers.utils.parseUnits('3000', await usbToken.decimals()));
    expect(await usbToken.totalSupply()).to.equal(ethers.utils.parseUnits('3000', await usbToken.decimals()));
    expect(await ethxToken.totalSupply()).to.equal(ethers.utils.parseUnits('2', await ethxToken.decimals()));

    // Asset Pool State: M_ETH = 3, M_USB = 3000, M_ETHx = 2, P_ETH = $2000
    // Bob deposite 3 ETH to mint $ETHx, expected output is: 3 * 2000 * 2 / (3 * 2000 - 3000) = 4
    ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    ethDepositAmount = ethers.utils.parseEther('3');
    expectedETHxAmount = ethers.utils.parseUnits('4', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(ethDepositAmount)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Bob).mintXTokens(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-3'), ethDepositAmount])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Bob.address, ethDepositAmount, expectedETHxAmount, ethPrice, await ethPriceFeed.decimals());
    
    // Asset Pool State: M_ETH = 6, M_USB = 3000, M_ETHx = 6, AAR: 6 * 2000 / 3000 = 400%
    // await dumpAssetPoolState(ethPool);
    expect(await ethPool.AAR()).to.equal(ethers.utils.parseUnits('4', await ethPool.AARDecimals()));
    expect(await ethPool.getAssetTotalAmount()).to.equal(ethers.utils.parseEther('6'));
    expect(await ethPool.usbTotalSupply()).to.equal(ethers.utils.parseUnits('3000', await usbToken.decimals()));
    expect(await usbToken.totalSupply()).to.equal(ethers.utils.parseUnits('3000', await usbToken.decimals()));
    expect(await ethxToken.totalSupply()).to.equal(ethers.utils.parseUnits('6', await ethxToken.decimals()));

    // ETH price falls to $700, AAR = 6 * 700 / 3000 = 140%
    // Expected behavior: $USB mint is paused, $ETHx mint is un-paused
    ethPrice = ethers.utils.parseUnits('700', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    expect(await ethPool.AAR()).to.equal(ethers.utils.parseUnits('1.4', await ethPool.AARDecimals()));
    ethDepositAmount = ethers.utils.parseEther('1');
    await expect(ethPool.calculateMintUSBOut(ethDepositAmount)).to.be.rejectedWith(/AAR Below Safe Threshold/);
    await expect(ethPool.connect(Caro).mintUSB(ethDepositAmount)).to.be.rejectedWith(/AAR Below Safe Threshold/);

    // Asset Pool State: M_ETH = 6, M_USB = 3000, M_ETHx = 6, AAR: 6 * 700 / 3000 = 140%
    // Caro deposite 3 ETH to mint $ETHx, expected output is: 3 * 700 * 6 / (6 * 700 - 3000) = 10.5
    // await dumpAssetPoolState(ethPool);
    ethDepositAmount = ethers.utils.parseEther('3');
    expectedETHxAmount = ethers.utils.parseUnits('10.5', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(ethDepositAmount)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Caro).mintXTokens(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Caro.address, ethPool.address], [ethers.utils.parseEther('-3'), ethDepositAmount])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Caro.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Caro.address, ethDepositAmount, expectedETHxAmount, ethPrice, await ethPriceFeed.decimals());

    // Asset Pool State: M_ETH = 9, M_USB = 3000, M_ETHx = 16.5
    // P_ETH = $300, AAR: 9 * 300 / 3000 = 90%,
    // Expected behavior: $USB mint is paused, $ETHx mint is paused for 1 hour
    await dumpAssetPoolState(ethPool);
    ethPrice = ethers.utils.parseUnits('300', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    expect(await ethPool.AAR()).to.equal(ethers.utils.parseUnits('0.9', await ethPool.AARDecimals()));
    ethDepositAmount = ethers.utils.parseEther('1');
    await expect(ethPool.connect(Alice).mintUSB(ethDepositAmount)).to.be.rejectedWith(/AAR Below Safe Threshold/);
    await expect(ethPool.connect(Alice).mintXTokens(ethDepositAmount)).to.be.rejectedWith("AAR Below 100%");

    // P_ETH = $350, AAR: 9 * 350 / 3000 = 105%
    ethPrice = ethers.utils.parseUnits('350', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    expect(await ethPool.AAR()).to.equal(ethers.utils.parseUnits('1.05', await ethPool.AARDecimals()));
    await expect(ethPool.connect(Alice).mintXTokens(ethDepositAmount)).to.be.rejectedWith(/AAR Below Circuit Breaker AAR Threshold/);

    // 1 hour later, $ETHx mint should be resumed
    // Expected $ETHx output is: 1 * 350 * 16.5 / (9 * 350 - 3000) = 38.5
    await expect(ethPool.connect(Alice).checkAAR()).not.to.be.reverted;
    const ONE_HOUR_IN_SECS = 60 * 60;
    expect(await ethPool.getParamValue(ethers.utils.formatBytes32String('CircuitBreakPeriod'))).to.equal(ONE_HOUR_IN_SECS);
    await dumpAssetPoolState(ethPool);
    await time.increase(ONE_HOUR_IN_SECS);
    expectedETHxAmount = ethers.utils.parseUnits('38.5', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(ethDepositAmount)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Alice).mintXTokens(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-1'), ethDepositAmount])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedETHxAmount, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    // Update M_ETH = 10, P_ETH = 350, M_USB = 3000, AAR: 10 * 350 / 3000 = 116.67%, C1 does not take effect
    // Alice redeem 3000 $USB, expected out:
    //  ETH: 3000 / 350 = 8.57142857143
    // Alice redeem 350 $USB, expected out:
    //  ETH: 350 / 350 = 1
    ethPrice = ethers.utils.parseUnits('350', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    let maxRedeemableUSBAmount = await ethPool.usbTotalSupply();
    let redeemedUSBAmount = ethers.utils.parseUnits('8.571428571428571428', await usbToken.decimals());
    let expectedFeeAmount = ethers.utils.parseEther('0');
    await expect(ethPool.connect(Alice).calculateRedemptionOutByUSB(maxRedeemableUSBAmount.add(1))).to.be.revertedWith(/Too large \$USB amount/);
    expect(await ethPool.calculateRedemptionOutByUSB(maxRedeemableUSBAmount)).to.deep.equal([redeemedUSBAmount, expectedFeeAmount]);
    redeemedUSBAmount = ethers.utils.parseUnits('350', await usbToken.decimals());
    let expectedETHAmount = ethers.utils.parseEther('1');
    expect(await ethPool.calculateRedemptionOutByUSB(redeemedUSBAmount)).to.deep.equal([expectedETHAmount, expectedFeeAmount]);

    // Update P_ETH = 270, AAR: 10 * 270 / 3000 = 90%
    // Alice redeem 3000 $USB, expectd out:
    //  ETH: 3000 * 10 / 3000 = 10
    // Alice redeem 270 $USB, expected out:
    //  ETH: 270 * 10 / 3000 = 0.9
    ethPrice = ethers.utils.parseUnits('270', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    maxRedeemableUSBAmount = await ethPool.usbTotalSupply();
    expectedETHAmount = ethers.utils.parseEther('10');
    expectedFeeAmount = ethers.utils.parseEther('0');
    expect(await ethPool.calculateRedemptionOutByUSB(maxRedeemableUSBAmount)).to.deep.equal([expectedETHAmount, expectedFeeAmount]);
    redeemedUSBAmount = ethers.utils.parseUnits('270', await usbToken.decimals());
    expectedETHAmount = ethers.utils.parseEther('0.9');
    expectedFeeAmount = ethers.utils.parseEther('0');
    expect(await ethPool.calculateRedemptionOutByUSB(redeemedUSBAmount)).to.deep.equal([expectedETHAmount, expectedFeeAmount]);

    // Asset Pool State: M_ETH = 10, M_USB = 3000, M_ETHx = 55, P_ETH = 350, AAR: 10 * 350 / 3000 = 116.67%
    // Update C1 = 10%, P_ETH = 1200, AAR: 400% (> 300%)
    // Alice redeem 120 $USB, expected out:
    //  ETH: 120 * (1 - 10%) / 1200 = 0.09
    //  Fee: 120 * 10% / 1200 = 0.01
    ethPrice = ethers.utils.parseUnits('1200', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("C1"), ethers.utils.parseUnits('0.1', await settings.decimals())))
      .to.emit(ethPool, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("C1"), ethers.utils.parseUnits('0.1', await settings.decimals()));
    expect(await ethPool.getParamValue(ethers.utils.formatBytes32String('C1'))).to.equal(ethers.utils.parseUnits('0.1', await settings.decimals()));
    redeemedUSBAmount = ethers.utils.parseUnits('120', await usbToken.decimals());
    expectedETHAmount = ethers.utils.parseEther('0.09');
    expectedFeeAmount = ethers.utils.parseEther('0.01');
    expect(await ethPool.calculateRedemptionOutByUSB(redeemedUSBAmount)).to.deep.equal([expectedETHAmount, expectedFeeAmount]);
    await expect(ethPool.connect(Alice).redeemByUSB(redeemedUSBAmount))
      .to.changeEtherBalances([ethPool.address, Alice.address, Ivy.address], [ethers.utils.parseEther('-0.1'), expectedETHAmount, expectedFeeAmount])
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, redeemedUSBAmount)
      .to.emit(ethPool, 'AssetRedeemedWithUSB').withArgs(Alice.address, redeemedUSBAmount, expectedETHAmount, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethPool, 'AssetRedeemedWithUSBFeeCollected').withArgs(Alice.address, Ivy.address, redeemedUSBAmount, expectedFeeAmount, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    // Asset Pool State: M_ETH = 9.9, M_USB = 2880, M_ETHx = 55, P_ETH = 1200, AAR: 9.9 * 1200 / 2880 = 4.125%
    // Update C2 to 1%
    // Alice redeems with 0.55 $ETHx, expected out:
    //  Paired $USB: 0.55 * 2880.0 / 55.0 = 28.8
    //  ETH: 0.55 * 9.9 * (1 - 1%) / 55 = 0.09801
    //  Fee: 0.55 * 9.9 * 1% / 55 = 0.00099
    // console.log(await ethxToken.balanceOf(Alice.address));
    // console.log(await usbToken.balanceOf(Alice.address));
    let redeemedETHxAmount = ethers.utils.parseUnits('0.55', await ethxToken.decimals());
    let expectedPairedUSBAmount = ethers.utils.parseUnits('28.8', await usbToken.decimals());
    expectedETHAmount = ethers.utils.parseEther('0.09801');
    expectedFeeAmount = ethers.utils.parseEther('0.00099');
    await expect(ethPool.connect(Alice).updateParamValue(ethers.utils.formatBytes32String("C2"), ethers.utils.parseUnits('0.01', await settings.decimals())))
      .to.emit(ethPool, 'UpdateParamValue').withArgs(ethers.utils.formatBytes32String("C2"), ethers.utils.parseUnits('0.01', await settings.decimals()));
    expect(await ethPool.getParamValue(ethers.utils.formatBytes32String('C2'))).to.equal(ethers.utils.parseUnits('0.01', await settings.decimals()));
    expect(await ethPool.calculatePairedUSBAmountToRedeemByXTokens(redeemedETHxAmount)).to.equal(expectedPairedUSBAmount);
    await expect(ethPool.connect(Alice).redeemByXTokens(redeemedETHxAmount))
      .to.changeEtherBalances([ethPool.address, Alice.address, Ivy.address], [ethers.utils.parseEther('-0.099'), expectedETHAmount, expectedFeeAmount])
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, expectedPairedUSBAmount)
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, redeemedETHxAmount)
      .to.emit(ethPool, 'AssetRedeemedWithXTokens').withArgs(Alice.address, redeemedETHxAmount, expectedPairedUSBAmount, expectedETHAmount, ethPrice, await ethPriceFeed.decimals())
      .to.emit(ethPool, 'AssetRedeemedWithXTokensFeeCollected').withArgs(Alice.address, Ivy.address, redeemedETHxAmount, expectedFeeAmount, expectedPairedUSBAmount, expectedETHAmount, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);
    
    // TODO: 
    //================== Special case: AAR drop below AARC for the first time, AAR' > AARC ==================

    //================== Special case: AAR drop below AARC for the first time, AAR' < AARC ==================
  
  });

  it('Dynamic AAR Adjustment for $USB->$ETHx Works', async () => {

    const {
      Alice, ethPriceFeed, wandProtocol, settings, usbToken, assetPoolFactory
    } = await loadFixture(deployContractsFixture);

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
        0, BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100),
        BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100), BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100),
        0, 0
      ])
    ).not.to.be.reverted;
    const ethPoolAddress = await assetPoolFactory.getAssetPoolAddress(ethAddress);
    await expect(ethxToken.connect(Alice).setAssetPool(ethPoolAddress)).not.to.be.reverted;
    const ethPool = AssetPool__factory.connect(ethPoolAddress, provider);

    // Set eth price to 2000; mint $USB and $ETHx
    let ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).mintXTokens(ethers.utils.parseEther("1"), {value: ethers.utils.parseEther("1")})).not.to.be.rejected;
    await expect(ethPool.connect(Alice).mintUSB(ethers.utils.parseEther("1"), {value: ethers.utils.parseEther("1")})).not.to.be.rejected;
    
    //================== Case: AAR > AART & AAR' > AART ==================

    // Asset Pool State: M_ETH = 2, M_USB = 2000, M_ETHx = 1, P_ETH = $2000, AAR = 200%
    // Set eth price to 3800, AAR = 380%
    // Expected behavior:
    //  - Alice swap 100 $USB for $ETHx
    //  - r = 0
    //  - AAR' = 2 * 3800 / (2000 - 100) = 400%
    //  - ΔETH = 100 * 1 * (1 + 0) / (2 * 3800 - 2000) = 0.01785714285
    ethPrice = ethers.utils.parseUnits('3800', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpAssetPoolState(ethPool);
    let usbAmountToSwap = ethers.utils.parseUnits('100', await usbToken.decimals());
    let expectedETHxAmount = ethers.utils.parseUnits('0.01785714285', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: AAR' < AARS ==================

    // Set eth price to 1140, AAR = 2 * 1140 / (2000 - 100) = 120%
    ethPrice = ethers.utils.parseUnits('1140', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).checkAAR()).not.to.be.reverted;
    const ONE_HOUR_IN_SECS = 60 * 60;
    await time.increase(ONE_HOUR_IN_SECS * 1.5);
    // 1.5 hours after AAR drop below 150%,
    // Asset Pool State: M_ETH = 2, M_USB = 1900, M_ETHx = 1.017857142857142857, P_ETH = $1140, AAR = 120%
    // Expected behavior:
    //  r = 0.1 * (200% - 150%) + 0.001 * 1.5 = 0.0515
    //  Alice swap 100 $USB for $ETHx
    //  AAR' = 2 * 1140 / (1900 - 100) = 1.26666666667
    //  ΔETH = 100 * 1.017857142857142857 * (1 + 0.0515) / (2 * 1140 - 1900) = 0.28165178571
    usbAmountToSwap = ethers.utils.parseUnits('100', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('0.28165178571', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅' ≤ 𝐴𝐴𝑅𝑇 𝑎𝑛𝑑 𝐴𝐴𝑅 ≤ 𝐴𝐴𝑅𝑆 ==================

    // Asset Pool State: M_ETH = 2, M_USB = 1800, M_ETHx = 1.299509002955357142, P_ETH = $1140, AAR = 126.6666667%
    // Expected behavior:
    //  r = 0.1 * (200% - 150%) + 0.001 * 1.5 = ~0.0515002777
    //  Alice swap 300 $USB for $ETHx
    //  AAR' = 2 * 1140 / (1800 - 300) = 1.52
    //  ΔETH = (1800 - 2 * 1140 / 1.5) * 1.299509002955357142 / (2 * 1140 - 1800) * (1 + 0.0515002777) +
    //    ((2 * 1140) / 1.5 + 300 - 1800) * 1.299509002955357142 / (2 * 1140 - 1800) *
    //    (1 + (2 * 2 - 1.5 - 1.52) * 0.1 / 2) = 0.85388591786
    usbAmountToSwap = ethers.utils.parseUnits('300', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('0.85388570735', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅' ≤ 𝐴𝐴𝑅𝑇 𝑎𝑛𝑑 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅 ≤ 𝐴𝐴𝑅𝑇 ==================

    // Asset Pool State: M_ETH = 2, M_USB = 1500, M_ETHx = 2.153395131409002895, P_ETH = $1140, AAR = 152%
    // Expected behavior:
    //  r = 0.1 * (200% - 152%) = 0.048
    //  Alice swap 100 $USB for $ETHx
    //  AAR' = 2 * 1140 / (1500 - 100) = 1.62857142857
    //  Δethx = Δusb * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (AAR'eth - AAReth) * 0.1 / 2)
    //  Δethx = Δusb * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (2 * AART - AAReth - AAR'eth) * 0.1 / 2)
    //  ΔETH = 100 * 2.153395131409002895 / (2 * 1140 - 1500) * (1 + (2 * 2.0 - 1.52 - 1.62857142857) * 0.1 / 2) = 0.28782926133
    usbAmountToSwap = ethers.utils.parseUnits('100', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('0.28782926133', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅' ≥ 𝐴𝐴𝑅𝑇 𝑎𝑛𝑑 𝐴𝐴𝑅 ≤ 𝐴𝐴𝑅𝑆 ==================

    // Set P_ETH = 1000, AAR = 2 * 1000 / 1400 = 1.42857142857
    ethPrice = ethers.utils.parseUnits('1000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).checkAAR()).not.to.be.reverted;
    await time.increase(ONE_HOUR_IN_SECS);

    // Asset Pool State: M_ETH = 2, M_USB = 1400, M_ETHx = 2.430970130208011746, P_ETH = $1000, AAR = 142.857142857%
    // Expected behavior:
    //  r = 0.1 * (200% - 150%) + 0.001 * 1 = 0.051
    //  Alice swap 500 $USB for $ETHx
    //  AAR' = 2 * 1000 / (1400 - 500) = 2.22222222222
    //  Δethx = (Musb-eth - M_ETH * P_ETH / S.AARS) * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + S.r)
    //    + (M_ETH * P_ETH / S.AARS - M_ETH * P_ETH / S.AART)
    //    * M_ETHx / (M_ETH * P_ETH - Musb-eth) * (1 + (S.AART - S.AARS) * 0.1 / 2)
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / S.AART) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    //  Δethx = (1400 - 2 * 1000 / 1.5) * 2.441224392726698966 / (2 * 1000 - 1400) * (1 + 0.051)
    //    + (2 * 1000 / 1.5 - 2 * 1000 / 2)
    //    * 2.441224392726698966 / (2 * 1000 - 1400) * (1 + (2 - 1.5) * 0.1 / 2)
    //    + (500 - 1400 + 2 * 1000 / 2) * 2.441224392726698966 / (2 * 1000 - 1400) = 2.08209315984
    await dumpAssetPoolState(ethPool);
    usbAmountToSwap = ethers.utils.parseUnits('500', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('2.08209315984', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅' ≥ 𝐴𝐴𝑅𝑇 𝑎𝑛𝑑 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅 ≤ 𝐴𝐴𝑅𝑇==================

    // Set P_ETH = 800, AAR = 2 * 800 / 900 = 1.77777777778
    ethPrice = ethers.utils.parseUnits('800', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;

    // Asset Pool State: M_ETH = 2, M_USB = 900, M_ETHx = 4.523317627893160645, P_ETH = $800, AAR = 177.777777778%
    // Expected behavior:
    //  r = 0.1 * (200% - 177.777777778%) = 0.02222222223
    //  Alice swap 200 $USB for $ETHx
    //  AAR' = 2 * 800 / (900 - 200) = 2.28571428571
    //  Δethx = (Musb-eth - M_ETH * P_ETH / S.AART) 
    //    * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    //    * (1 + (S.AART - AAReth) * 0.1 / 2)
    //    + (Δusb - Musb-eth + M_ETH * P_ETH / S.AART) * M_ETHx / (M_ETH * P_ETH - Musb-eth)
    //  Δethx = (900 - 2 * 800 / 2) * 4.523317627893160645 / (2 * 800 - 900) * (1 + (2 - 1.77777777778) * 0.1 / 2)
    //    + (200 - 900 + 2 * 800 / 2) * 4.523317627893160645 / (2 * 800 - 900) = 1.29955633436
    usbAmountToSwap = ethers.utils.parseUnits('200', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('1.29955633436', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Special case: AAR drop below AARC for the first time, AAR' > AARC ==================

    // Asset Pool State: M_ETH = 2, M_USB = 700, M_ETHx = 5.822873962248936452, P_ETH = $800, AAR = 2.2857142857
    // Set P_ETH = 360, AAR = 2 * 360 / 700 = 1.02857142857
    // Expected behavior:
    //  r = 0.1 * (200% - 150%) + 0.001 * 0 = 0.05
    //  Alice swap 100 $USB for $ETHx
    //  AAR' = 2 * 360 / (700 - 100) = 1.2
    //  Δethx = Δusb * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth)
    //  Δethx = 100 * 5.822873962248936452 * (1 + 0.05) / (2 * 360 - 700) = 30.5700883018
    //  After swap, AARBelowSafeLineTime and AARBelowCircuitBreakerLineTime is updated
    ethPrice = ethers.utils.parseUnits('360', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    expect(await ethPool.AARBelowSafeLineTime()).to.equal(0);
    expect(await ethPool.AARBelowCircuitBreakerLineTime()).to.equal(0);
    usbAmountToSwap = ethers.utils.parseUnits('100', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('30.5700883018', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);
    expect(await ethPool.AARBelowSafeLineTime()).to.greaterThan(0);
    expect(await ethPool.AARBelowCircuitBreakerLineTime()).to.equal(0);

    //================== Special case: AAR drop below AARC for the first time, AAR' < AARC ==================

    // Asset Pool State: M_ETH = 2, M_USB = 600, M_ETHx = 36.392962264055852825, P_ETH = $360, AAR = 1.2
    // 1 hour later, Set P_ETH = 303, AAR = 2 * 303 / 600 = 1.01
    // Expected behavior:
    //  r = 0.1 * (200% - 150%) + 0.001 * 1 = 0.051
    //  Alice swap 10 $USB for $ETHx
    //  AAR' = 2 * 303 / (600 - 10) = 1.02711864407
    //  Δethx = Δusb * M_ETHx * (1 + r) / (M_ETH * P_ETH - Musb-eth)
    //  Δethx = 10 * 36.392962264055852825 * (1 + 0.051) / (2 * 303 - 600) = 63.7483388992
    await time.increase(ONE_HOUR_IN_SECS);
    ethPrice = ethers.utils.parseUnits('303', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    usbAmountToSwap = ethers.utils.parseUnits('10', await usbToken.decimals());
    expectedETHxAmount = ethers.utils.parseUnits('63.7483388992', await ethxToken.decimals());
    expectBigNumberEquals(await ethPool.calculateUSBToXTokensOut(usbAmountToSwap), expectedETHxAmount);
    await expect(ethPool.connect(Alice).usbToXTokens(usbAmountToSwap))
      .to.emit(usbToken, 'Transfer').withArgs(Alice.address, ethers.constants.AddressZero, usbAmountToSwap)
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, anyValue)
      .to.emit(ethPool, 'UsbToXTokens').withArgs(Alice.address, usbAmountToSwap, anyValue, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);
    expect(await ethPool.AARBelowSafeLineTime()).to.greaterThan(0);
    expect(await ethPool.AARBelowCircuitBreakerLineTime()).to.greaterThan(0);

    // Now $USB -> $ETHx swap is disabled
    await expect(ethPool.calculateUSBToXTokensOut(usbAmountToSwap)).to.be.revertedWith("AAR Below Circuit Breaker AAR Threshold");

    //================== Special case: AAR drop below AARC for the first time, AAR' <= 100% ==================

    // Asset Pool State: M_ETH = 2, M_USB = 590, M_ETHx = 99.720695304378183102, P_ETH = $303, AAR = 1.027118644
    // Set P_ETH = 260, AAR = 2 * 260 / 590 = 0.8813559322
    await time.increase(ONE_HOUR_IN_SECS * 2);
    ethPrice = ethers.utils.parseUnits('260', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.calculateUSBToXTokensOut(usbAmountToSwap)).to.be.revertedWith("AAR Below 100%");

  });

  it('Dynamic AAR Adjustment for $USB mint Works', async () => {

    const {
      Alice, ethPriceFeed, wandProtocol, settings, usbToken, assetPoolFactory
    } = await loadFixture(deployContractsFixture);

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
        0, BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100),
        BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100), BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100),
        0, 0
      ])
    ).not.to.be.reverted;
    const ethPoolAddress = await assetPoolFactory.getAssetPoolAddress(ethAddress);
    await expect(ethxToken.connect(Alice).setAssetPool(ethPoolAddress)).not.to.be.reverted;
    const ethPool = AssetPool__factory.connect(ethPoolAddress, provider);

    // Set eth price to 2000; mint $USB and $ETHx
    let ethPrice = ethers.utils.parseUnits('2000', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpAssetPoolState(ethPool);
    await expect(ethPool.connect(Alice).mintXTokens(ethers.utils.parseEther("1"), {value: ethers.utils.parseEther("1")})).not.to.be.rejected;
    await expect(ethPool.connect(Alice).mintUSB(ethers.utils.parseEther("1"), {value: ethers.utils.parseEther("1")})).not.to.be.rejected;
    
    //================== Case: AAR > AART & AAR' > AART ==================

    // Asset Pool State: M_ETH = 2, M_USB = 2000, M_ETHx = 1, P_ETH = $2000, AAR = 200%
    // Set eth price to 3800, AAR = 380%
    // Expected behavior:
    //  - Alice deposit 0.3 ETH to mint $USB
    //  - R2 = 0
    //  - AAR' = (2 + 0.3) * 3800 / (2000 + 0.3 * 3800) = 2.78343949045
    //  - Δusb = Δeth * P_ETH
    //  - Δusb = 0.3 * 3800 = 1140
    ethPrice = ethers.utils.parseUnits('3800', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await dumpAssetPoolState(ethPool);
    let ethAmountToDeposit = ethers.utils.parseEther('0.3');
    let expectedUSBAmount = ethers.utils.parseUnits('1140', await usbToken.decimals());
    expectBigNumberEquals(await ethPool.calculateMintUSBOut(ethAmountToDeposit), expectedUSBAmount);
    await expect(ethPool.connect(Alice).mintUSB(ethAmountToDeposit, {value: ethAmountToDeposit}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-0.3'), ethAmountToDeposit])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedUSBAmount)
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, ethAmountToDeposit, expectedUSBAmount, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅' ≤ 𝐴𝐴𝑅𝑇 𝑎𝑛𝑑 𝐴𝐴𝑅 ≥ 𝐴𝐴𝑅𝑇 ==================

    // Asset Pool State: M_ETH = 2.3, M_USB = 3140, M_ETHx = 1, P_ETH = $3800, AAR = 2.7834394904
    // Expected behavior:
    //  - Alice deposit 1 ETH to mint $USB
    //  - R2 = 0
    //  - AAR' = (2.3 + 1) * 3800 / (3140 + 1 * 3800) = 1.80691642651
    //  - Δusb = (M_ETH * P_ETH - AART * Musb-eth) / (AART - 1)
    //    + (Δeth * P_ETH - (M_ETH * P_ETH - AART * Musb-eth) / (AART - 1))
    //    * (1 - (AART - AAR'eth) * 0.06 / 2)
    //  - Δusb = (2.3 * 3800 - 2 * 3140) / (2 - 1)
    //    + (1 * 3800 - (2.3 * 3800 - 2 * 3140) / (2 - 1))
    //    * (1 - (2 - 1.80691642651) * 0.06 / 2) = 3792.23804035
    ethAmountToDeposit = ethers.utils.parseEther('1');
    expectedUSBAmount = ethers.utils.parseUnits('3792.238040352', await usbToken.decimals());
    expectBigNumberEquals(await ethPool.calculateMintUSBOut(ethAmountToDeposit), expectedUSBAmount);
    await expect(ethPool.connect(Alice).mintUSB(ethAmountToDeposit, {value: ethAmountToDeposit}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-1'), ethAmountToDeposit])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedUSBAmount)
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, ethAmountToDeposit, expectedUSBAmount, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅' ≤ 𝐴𝐴𝑅𝑇 𝑎𝑛𝑑 𝐴𝐴𝑅𝑆 ≤ 𝐴𝐴𝑅 ≤ 𝐴𝐴𝑅𝑇 ==================

    // Asset Pool State: M_ETH = 3.3, M_USB = 6932.238040352, M_ETHx = 1, P_ETH = $3800, AAR = 1.8089396132
    // Expected behavior
    //  - Alice deposit 1 ETH to mint $USB
    //  - R2 = 0.06 * (2 - 1.8089396132) = 0.0114636232
    //  - AAR' = (3.3 + 1) * 3800 / (6932.238040352 + 1 * 3800) = 1.52251561497
    //  - Δusb = Δeth * P_ETH * (1 - (2 * AART - AAReth - AAR'eth) * 0.06 / 2)
    //  - Δusb = 1 * 3800 * (1 - (2 * 2 - 1.8089396132 - 1.52251561497) * 0.06 / 2) = 3723.78589601
    ethAmountToDeposit = ethers.utils.parseEther('1');
    expectedUSBAmount = ethers.utils.parseUnits('3723.78589622', await usbToken.decimals());
    expectBigNumberEquals(await ethPool.calculateMintUSBOut(ethAmountToDeposit), expectedUSBAmount);
    await expect(ethPool.connect(Alice).mintUSB(ethAmountToDeposit, {value: ethAmountToDeposit}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-1'), ethAmountToDeposit])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedUSBAmount)
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, ethAmountToDeposit, expectedUSBAmount, ethPrice, await ethPriceFeed.decimals());
    await dumpAssetPoolState(ethPool);

    //================== Case: 𝐴𝐴𝑅' ≤ 𝐴𝐴𝑅𝑆 ==================

    // Asset Pool State: M_ETH = 4.3, M_USB = 10656.023936572, M_ETHx = 1, P_ETH = $3800, AAR = 1.5334049639
    // Expected behavior
    //  - Alice deposit 1 ETH to mint $USB
    //  - R2 = 0.06 * (2 - 1.5334049639) = 0.02799570216
    //  - AAR' = (4.3 + 1) * 3800 / (10656.023936572 + 1 * 3800) = 1.39319083092
    ethAmountToDeposit = ethers.utils.parseEther('1');
    await expect(ethPool.connect(Alice).mintUSB(ethAmountToDeposit)).to.be.rejectedWith(/AAR Below Safe Threshold after Mint/);

  });
});