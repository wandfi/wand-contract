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

    // Day 1. Suppose ETH price is $2000. Alice deposit 1 ETH to mint 2000 $USB
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS);
    // await expect(ethPool.connect(Alice).mintUSB(bobStakeAmount))
    //   .to.changeEtherBalances([Bob.address, weth.address], [ethers.utils.parseEther('-0.0089'), ethers.utils.parseEther('0.0089')])
    //   .to.emit(, 'Transfer').withArgs(Bob.address, rewardBooster.address, bobStakeAmount)
    //   .to.emit(rewardBooster, 'Stake').withArgs(Bob.address, nextStakeId, bobStakeAmount);

  });

});