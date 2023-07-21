import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  AssetPoolFactory__factory,
  InterestPoolFactory__factory,
  AssetPool__factory,
  AssetX__factory,
} from '../typechain';

const { BigNumber } = ethers;

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const deployer = new ethers.Wallet(privateKey, provider);
const wbtcAddress = '0x183c07F248e137E964E213925d0cfd0d3DCd8f1C';
const ethPriceFeedAddress = '0x05acAAe839d572D45109ef9EbbBB200AA7b0bB05';
const wbtcPriceFeedAddress = '0xCD1d9898453d49F947e518d1F2776CEd580095F2';
const treasuryAddress = deployer.address;

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  // const deployer = new ethers.Wallet(privateKey, provider);

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  const WandProtocol = await WandProtocolFactory.deploy();
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);
  console.log(`Deployed WandProtocol to ${wandProtocol.address}`);
  // const wandProtocol = WandProtocol__factory.connect('0x6B4cB7784Ffa7b940fC4EB917bbf1B69bD1628DD', provider);

  const ProtocolSettingsFactory = await ethers.getContractFactory('ProtocolSettings');
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(wandProtocol.address, treasuryAddress);
  const settings = ProtocolSettings__factory.connect(ProtocolSettings.address, provider);
  console.log(`ProtocolSettings address: ${settings.address}`);
  let trans = await wandProtocol.connect(deployer).setSettings(settings.address);
  await trans.wait();

  const USBFactory = await ethers.getContractFactory('USB');
  const USB = await USBFactory.deploy(wandProtocol.address, "USB Token", "USB");
  const usbToken = USB__factory.connect(USB.address, provider);
  console.log(`$USB token address: ${usbToken.address}`);
  trans = await wandProtocol.connect(deployer).setUsbToken(usbToken.address);
  await trans.wait();

  const AssetPoolFactoryFactory = await ethers.getContractFactory('AssetPoolFactory');
  const AssetPoolFactory = await AssetPoolFactoryFactory.deploy(wandProtocol.address, usbToken.address);
  const assetPoolFactory = AssetPoolFactory__factory.connect(AssetPoolFactory.address, provider);
  console.log(`Deployed AssetPoolFactory to ${assetPoolFactory.address}`);
  trans = await wandProtocol.connect(deployer).setAssetPoolFactory(assetPoolFactory.address);
  await trans.wait();
  console.log(`Set WandProtocol.AssetPoolFactory to ${assetPoolFactory.address}`);

  const InterestPoolFactoryFactory = await ethers.getContractFactory('InterestPoolFactory');
  const InterestPoolFactory = await InterestPoolFactoryFactory.deploy(wandProtocol.address);
  const interestPoolFactory = InterestPoolFactory__factory.connect(InterestPoolFactory.address, provider);
  console.log(`Deployed InterestPoolFactory to ${interestPoolFactory.address}`);
  trans = await wandProtocol.connect(deployer).setInterestPoolFactory(interestPoolFactory.address);
  await trans.wait();
  console.log(`Set WandProtocol.InterestPoolFactory to ${interestPoolFactory.address}`);

  // Create ETH asset pool
  const ethAddress = nativeTokenAddress;
  const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(35).div(1000);  // 3.5%
  const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
  trans = await wandProtocol.connect(deployer).addAssetPool(ethAddress, ethPriceFeedAddress, "ETHx Token", "ETHx", ethY, ethAART, ethAARS, ethAARC);
  await trans.wait();
  console.log(`Created ETH asset pool`);
  const ethPoolInfo = await assetPoolFactory.getAssetPoolInfo(ethAddress);
  const ethPool = AssetPool__factory.connect(ethPoolInfo.pool, provider);
  const ethxToken = AssetX__factory.connect(ethPoolInfo.xToken, provider);

  // Create WBTC asset pool
  const wbtcY = BigNumber.from(10).pow(await settings.decimals()).mul(30).div(1000);  // 3%
  const wbtcAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const wbtcAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const wbtcAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
  trans = await wandProtocol.connect(deployer).addAssetPool(wbtcAddress, wbtcPriceFeedAddress, "WBTCx Token", "WBTCx", wbtcY, wbtcAART, wbtcAARS, wbtcAARC);
  await trans.wait();
  console.log(`Created WBTC asset pool`);
  const wbtcPoolInfo = await assetPoolFactory.getAssetPoolInfo(wbtcAddress);
  const wbtcPool = AssetPool__factory.connect(wbtcPoolInfo.pool, provider);
  const wbtcxToken = AssetX__factory.connect(wbtcPoolInfo.xToken, provider);

  console.log(`Contract addresses:`);
  console.log(`\tWandProtocol address: ${WandProtocol.address}`);
  console.log(`\tProtocolSettings address: ${settings.address}`);
  console.log(`\t$USB token address: ${usbToken.address}`);
  console.log(`\tAssetPoolFactory address: ${assetPoolFactory.address}`);
  console.log(`\t\tETH Asset Pool address: ${ethPool.address}`);
  console.log(`\t\t$ETHx Token address: ${ethxToken.address}`);
  console.log(`\t\tWBTC Asset Pool address: ${wbtcPool.address}`);
  console.log(`\t\t$WBTCx Token address: ${wbtcxToken.address}`);
  console.log(`\tInterestPoolFactory address: ${interestPoolFactory.address}`);
  console.log(`\t\t$USB InterestPool address: ${await interestPoolFactory.getInterestPoolAddress(usbToken.address)}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});