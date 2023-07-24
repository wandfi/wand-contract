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
      Alice, Bob, Caro, Dave, Ivy, ethPriceFeed,
      wandProtocol, settings, usbToken, assetPoolFactory, interestPoolFactory
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

    // Initial AAR should be max uint256
    expect (await ethPool.AAR()).to.equal(ethers.constants.MaxUint256);

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
    // await dumpAssetPoolState(ethPool);
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

    // Update P_ETH = 350, AAR: 10 * 350 / 3000 = 116.67%, C1 does not take effect
    // Alice redeem 350 $USB, expected out:
    //  ETH: 350 / 350 = 1
    ethPrice = ethers.utils.parseUnits('350', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    let redeemedUSBAmount = ethers.utils.parseUnits('350', await usbToken.decimals());
    let expectedETHAmount = ethers.utils.parseEther('1');
    let expectedFeeAmount = ethers.utils.parseEther('0');
    expect(await ethPool.calculateRedemptionOutByUSB(redeemedUSBAmount)).to.deep.equal([expectedETHAmount, expectedFeeAmount]);

    // Update P_ETH = 270, AAR: 10 * 270 / 3000 = 90%
    // Alice redeem 270 $USB, expected out:
    //  ETH: 270 * 10 / 3000 = 0.9
    ethPrice = ethers.utils.parseUnits('270', await ethPriceFeed.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
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



  });

});