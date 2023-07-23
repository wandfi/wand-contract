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

const wbtcAddress = '0x183c07F248e137E964E213925d0cfd0d3DCd8f1C';
const ethPriceFeedAddress = '0x05acAAe839d572D45109ef9EbbBB200AA7b0bB05';
const wbtcPriceFeedAddress = '0xCD1d9898453d49F947e518d1F2776CEd580095F2';

const protocolSettingsAddress = '0x32995491E0B6EcAebd51dfF140B0526041f83c57';
const wandProtocolAddress = '0xcfb2d127b8CB9D8cEc75E02674B2D6B931A87038';
const usbTokenAddress = '0x807D699594fD12D1dD8448B026EA1361b65D75c4';
const assetPoolFactoryAddress = '0x325B450F3f9eBc231948A5Dc2b8e9D0cc6B70b36';
const interestPoolFactoryAddress = '0x895eb3893068296c03915509B943d9Fe27D49b08';

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
  const settings = ProtocolSettings__factory.connect(protocolSettingsAddress, provider);
  const assetPoolFactory = AssetPoolFactory__factory.connect(assetPoolFactoryAddress, provider);
  const interestPoolFactory = InterestPoolFactory__factory.connect(interestPoolFactoryAddress, provider);
  const usbToken = USB__factory.connect(usbTokenAddress, provider);

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
  const wbtcxPoolAddress = await assetPoolFactory.getAssetPoolAddress(wbtcAddress);
  console.log(`Deployed $WBTC asset pool to ${wbtcxPoolAddress}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});