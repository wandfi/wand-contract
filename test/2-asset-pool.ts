import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { nativeTokenAddress, deployContractsFixture, dumpAssetPoolState, expectBigNumberEquals } from './utils';
import { 
  AssetPool__factory,
  AssetX__factory,
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Asset Pool', () => {

  it('Mint & Redemption (Without Interest & Fees) Works', async () => {

    const {
      Alice, Bob, Caro, ethPriceFeed,
      wandProtocol, settings, usbToken, assetPoolFactory, interestPoolFactory
    } = await loadFixture(deployContractsFixture);
    
    // Create ETH asset pool
    const ethAddress = nativeTokenAddress;
    const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(0).div(10000);  // 0%
    const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
    await expect(wandProtocol.connect(Alice).addAssetPool(ethAddress, ethPriceFeed.address, "ETHx Token", "ETHx", ethY, ethAART, ethAARS, ethAARC))
      .to.emit(assetPoolFactory, 'AssetPoolAdded').withArgs(ethAddress, ethPriceFeed.address, anyValue)
      .to.emit(interestPoolFactory, 'InterestPoolAdded').withArgs(usbToken.address, 0 /* InterestPoolStakingTokenType.Usb */, anyValue, anyValue);
    const ethPoolInfo = await assetPoolFactory.getAssetPoolInfo(ethAddress);
    const ethPool = AssetPool__factory.connect(ethPoolInfo.pool, provider);
    const ethxToken = AssetX__factory.connect(ethPoolInfo.xToken, provider);

    // Initial AAR should be max uint256
    expect (await ethPool.AAR()).to.equal(ethers.constants.MaxUint256);

    // Set C1 & C2 to 0 to faciliate testing
    await expect(wandProtocol.connect(Alice).setC1(ethAddress, 0))
      .to.emit(ethPool, 'UpdatedC1').withArgs(await settings.defaultC1(), 0);
    await expect(wandProtocol.connect(Alice).setC2(ethAddress, 0))
      .to.emit(ethPool, 'UpdatedC2').withArgs(await settings.defaultC2(), 0);

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
    await expect(ethPriceFeed.connect(Bob).mockPrice(ethPrice)).not.to.be.reverted;
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
    await expect(ethPriceFeed.connect(Bob).mockPrice(ethPrice)).not.to.be.reverted;
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
    await expect(ethPriceFeed.connect(Caro).mockPrice(ethPrice)).not.to.be.reverted;
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

    // Asset Pool State: M_ETH = 9, M_USB = 3000, M_ETHx = 16.5, AAR: 9 * 700 / 3000 = 210%
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
    await expect(ethPool.connect(Alice).mintXTokens(ethDepositAmount)).to.be.rejectedWith(/AAR Below Safe Threshold/);

    // 1 hour later, $ETHx mint should be resumed
    // Expected $ETHx output is: 1 * 350 * 16.5 / (9 * 350 - 3000) = 38.5
    await expect(ethPool.connect(Alice).checkAAR()).not.to.be.reverted;
    const ONE_HOUR_IN_SECS = 60 * 60;
    expect(await ethPool.CiruitBreakPeriod()).to.equal(ONE_HOUR_IN_SECS);
    await dumpAssetPoolState(ethPool);
    await time.increase(ONE_HOUR_IN_SECS);
    expectedETHxAmount = ethers.utils.parseUnits('38.5', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(ethDepositAmount)).to.equal(expectedETHxAmount);
    await expect(ethPool.connect(Alice).mintXTokens(ethDepositAmount, {value: ethDepositAmount}))
      .to.changeEtherBalances([Alice.address, ethPool.address], [ethers.utils.parseEther('-1'), ethDepositAmount])
      .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Alice.address, expectedETHxAmount)
      .to.emit(ethPool, 'XTokenMinted').withArgs(Alice.address, ethDepositAmount, expectedETHxAmount, ethPrice, await ethPriceFeed.decimals());
    


  });

});