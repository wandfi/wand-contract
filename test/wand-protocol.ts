import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ONE_DAY_IN_SECS, nativeTokenAddress, deployContractsFixture, expandTo18Decimals, expectBigNumberEquals } from './utils';
import { 
  AssetPool__factory,
  AssetX__factory,
  ERC20Mock__factory,
  InterestPool__factory,
  WandProtocol__factory
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
    
    // Create ETH asset pool
    const ethAddress = nativeTokenAddress;
    const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(35).div(1000);  // 3.5%
    const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
    await expect(wandProtocol.connect(Alice).addAssetPool(ethAddress, ethPriceFeed.address, "ETHx Token", "ETHx", ethY, ethAART, ethAARS, ethAARC))
      .to.emit(assetPoolFactory, 'AssetPoolAdded').withArgs(ethAddress, ethPriceFeed.address, anyValue)
      .to.emit(interestPoolFactory, 'InterestPoolAdded').withArgs(usbToken.address, 0 /* InterestPoolStakingTokenType.Usb */, anyValue, anyValue);
    
    // Check ETH asset pool is created; ETHx token is deployed; and an interest pool for $USB -> $ETHx is created
    const ethPoolInfo = await assetPoolFactory.getAssetPoolInfo(ethAddress);
    expect(ethPoolInfo.assetToken).to.equal(ethAddress);
    expect(ethPoolInfo.assetPriceFeed).to.equal(ethPriceFeed.address);
    const ethPool = AssetPool__factory.connect(ethPoolInfo.pool, provider);
    const ethxToken = AssetX__factory.connect(ethPoolInfo.xToken, provider);

    expect(await interestPoolFactory.poolExists(usbToken.address)).to.be.true;
    const usbInterestPool = InterestPool__factory.connect(await interestPoolFactory.getInterestPoolAddress(usbToken.address), provider);
    // expect((await usbInterestPool.rewardTokens())[0]).to.equal(ethxToken.address);
    expect(await usbInterestPool.rewardTokenAdded(ethxToken.address)).to.be.true;

    // Create $WBTC asset pool
    const wbtcY = BigNumber.from(10).pow(await settings.decimals()).mul(30).div(1000);  // 3%
    const wbtcAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
    const wbtcAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
    const wbtcAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
    await expect(wandProtocol.connect(Alice).addAssetPool(wbtc.address, wbtcPriceFeed.address, "WBTCx Token", "WBTCx", wbtcY, wbtcAART, wbtcAARS, wbtcAARC))
      .to.emit(assetPoolFactory, 'AssetPoolAdded').withArgs(wbtc.address, wbtcPriceFeed.address, anyValue)
      .to.emit(usbInterestPool, 'RewardTokenAdded').withArgs(anyValue);
    
    // Check $WBTCx is added as a reward token to $USB interest pool
    const wbtcPool = AssetPool__factory.connect((await assetPoolFactory.getAssetPoolInfo(wbtc.address)).pool, provider);
    const wbtcxToken = AssetX__factory.connect(await wbtcPool.xToken(), provider);
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
      .to.emit(ethPool, 'USBMinted').withArgs(Alice.address, aliceDepositETH, expectedUsbAmount);
    expect(await usbToken.balanceOf(Alice.address)).to.equal(expectedUsbAmount);

    //  Day 2. ETH price is $3000. Bob deposit 1 ETH to mint 3000 $USB
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);
    const ethPrice2 = ethers.utils.parseUnits('3000', await ethPriceFeed.decimals());
    const bobDepositETH = ethers.utils.parseEther('1');
    const expectedUsbAmount2 = ethers.utils.parseUnits('3000', await usbToken.decimals());
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice2)).not.to.be.reverted;
    expect(await ethPool.calculateMintUSBOut(bobDepositETH)).to.equal(expectedUsbAmount2);
    await expect(ethPool.connect(Bob).mintUSB(bobDepositETH, {value: bobDepositETH}))
      .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-1'), bobDepositETH])
      .to.emit(usbToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, expectedUsbAmount2)
      .to.emit(ethPool, 'USBMinted').withArgs(Bob.address, bobDepositETH, expectedUsbAmount2);
    
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
      .to.emit(ethPool, 'XTokenMinted').withArgs(Caro.address, caroDepositETH, expectedETHxAmount);

    // Bob deposit 1 ETH to mint $ETH
    // Expected amount: (1 * $3500 * 4) / (7 * $3500 - 7000) = 0.8
    const bobDepositETH2 = ethers.utils.parseEther('1');
    const expectedETHxAmount2 = ethers.utils.parseUnits('0.8', await ethxToken.decimals());
    expect(await ethPool.calculateMintXTokensOut(bobDepositETH2)).to.equal(expectedETHxAmount2);
    // await expect(ethPool.connect(Bob).mintXTokens(bobDepositETH2, {value: bobDepositETH2}))
    //   .to.changeEtherBalances([Bob.address, ethPool.address], [ethers.utils.parseEther('-1'), bobDepositETH2])
    //   .to.emit(ethxToken, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, expectedETHxAmount2)
    //   .to.emit(ethPool, 'XTokenMinted').withArgs(Bob.address, bobDepositETH2, expectedETHxAmount2);


  });

});