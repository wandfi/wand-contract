import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  AssetPoolFactory__factory,
  InterestPoolFactory__factory,
  AssetX__factory,
  AssetPool__factory,
  UsbInterestPool__factory
} from '../typechain';

const { BigNumber } = ethers;

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const deployer = new ethers.Wallet(privateKey, provider);

// Based on Chainlink price feed for ETH/USD on Goerli
// https://goerli.etherscan.io/address/0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
const ethPriceFeedAddress = '0x2f7DA0085A66599CEbC4d5fFc7d53d1C7711cf3e';

const wbtcAddress = '0x25d8D02457C9FAB1f0a3CD4Fa4B526Eb32f81114';
const wbtcPriceFeedAddress = '0x1BDCF0d340cD22277A345Df4cfecc0C78EeBDEE8'; // Mocked price feed for WBTC/USD on Goerli

const stethAddress = '0x9d098c1d4d628013344ac8927c681b55bec49666';
const stethPriceFeedAddress = '0x02BF5dd6C1BE5C5c2BD8168A9Eb6cB03F38D6E17'; // Mocked price feed for stETH/USD on Goerli

const wandProtocolAddress = '0x523411921f0089E05A29897D600D0d64fA88f218';

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

/**
 * Deployment sequence:
 *  - Deploy ProtocolSettings
 *  - Deploy WandProtocol
 *  - Deploy USB
 *  - Deploy AssetPoolCalculator
 *  - Deploy AssetPoolFactory
 *  - Deploy InterestPoolFactory
 *  - Register USB/AssetPoolCalculator/AssetPoolFactory/InterestPoolFactory to WandProtocol
 * 
 *  - Create AssetPools
 *    - Deploy AssetX (WandProtocol.addAssetPool)
 *    - Create AssetPool
 *    - Set AssetPool to AssetX
 *  - Create InterestPools
 *   - Deploy $USB InterestPool
 *   - Notifiy InterestPoolFactory
 */
async function main() {
  const wandProtocol = WandProtocol__factory.connect(wandProtocolAddress, provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);
  const assetPoolFactory = AssetPoolFactory__factory.connect(await wandProtocol.assetPoolFactory(), provider);
  const interestPoolFactory = InterestPoolFactory__factory.connect(await wandProtocol.interestPoolFactory(), provider);
  const usbToken = USB__factory.connect(await wandProtocol.usbToken(), provider);

  // Create $ETHx token
  const AssetXFactory = await ethers.getContractFactory('AssetX');
  const ETHx = await AssetXFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
  const ethxToken = AssetX__factory.connect(ETHx.address, provider);
  console.log(`Deployed $ETHx token to ${ethxToken.address}`);
  
  // Create ETH asset pool
  const ethAddress = nativeTokenAddress;
  const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(365).div(10000);  // 3.65%
  const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
  let trans = await wandProtocol.connect(deployer).addAssetPool(
    ethAddress, ethPriceFeedAddress, ethxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [ethY, ethAART, ethAARS, ethAARC]
  );
  await trans.wait();

  const ethPoolAddress = await assetPoolFactory.getAssetPoolAddress(ethAddress);
  const ethPool = AssetPool__factory.connect(ethPoolAddress, provider);
  console.log(`Deployed $ETH asset pool to ${ethPoolAddress}`);

  trans = await ethxToken.connect(deployer).setAssetPool(ethPoolAddress);
  await trans.wait();
  console.log(`Connected $ETH asset pool to $ETHx token`);

  // Deploy $USB InterestPool
  const UsbInterestPoolFactory = await ethers.getContractFactory('UsbInterestPool');
  const UsbInterestPool = await UsbInterestPoolFactory.deploy(wandProtocol.address, interestPoolFactory.address, usbToken.address, [ethxToken.address]);
  const usbInterestPool = UsbInterestPool__factory.connect(UsbInterestPool.address, provider);
  console.log(`Deployed $USB interest pool to ${usbInterestPool.address}`);
  trans = await interestPoolFactory.connect(deployer).notifyInterestPoolAdded(usbToken.address, usbInterestPool.address);
  await trans.wait();
  console.log(`Registered $USB interest pool to InterestPoolFactory`);
  
  // Create $WBTC asset pool
  const WBTCx = await AssetXFactory.deploy(wandProtocol.address, "WBTCx Token", "WBTCx");
  const wbtcxToken = AssetX__factory.connect(WBTCx.address, provider);
  console.log(`Deployed $WBTCx token to ${wbtcxToken.address}`);

  const wbtcY = BigNumber.from(10).pow(await settings.decimals()).mul(30).div(1000);  // 3%
  const wbtcAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const wbtcAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const wbtcAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
  trans = await wandProtocol.connect(deployer).addAssetPool(
    wbtcAddress, wbtcPriceFeedAddress, wbtcxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [wbtcY, wbtcAART, wbtcAARS, wbtcAARC]
  );
  await trans.wait();
  const wbtcPoolAddress = await assetPoolFactory.getAssetPoolAddress(wbtcAddress);
  console.log(`Deployed $WBTC asset pool to ${wbtcPoolAddress}`);

  trans = await wbtcxToken.connect(deployer).setAssetPool(wbtcPoolAddress);
  await trans.wait();
  console.log(`Connected $WBTCx asset pool to $WBTCx token`);

  // Create $stETH asset pool
  const stETHx = await AssetXFactory.deploy(wandProtocol.address, "stETHx Token", "stETHx");
  const stethxToken = AssetX__factory.connect(stETHx.address, provider);
  console.log(`Deployed $stETHx token to ${stethxToken.address}`);

  const stethY = BigNumber.from(10).pow(await settings.decimals()).mul(50).div(1000);  // 5%
  const stethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const stethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const stethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
  trans = await wandProtocol.connect(deployer).addAssetPool(
    stethAddress, stethPriceFeedAddress, stethxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [stethY, stethAART, stethAARS, stethAARC]
  );
  await trans.wait();
  const stethPoolAddress = await assetPoolFactory.getAssetPoolAddress(stethAddress);
  console.log(`Deployed $stETH asset pool to ${stethPoolAddress}`);

  trans = await stethxToken.connect(deployer).setAssetPool(stethPoolAddress);
  await trans.wait();
  console.log(`Connected $stETHx asset pool to $stETHx token`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});