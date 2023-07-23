import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  AssetPoolFactory__factory,
  InterestPoolFactory__factory,
  AssetPoolCalculator__factory
} from '../typechain';

const { BigNumber } = ethers;

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const deployer = new ethers.Wallet(privateKey, provider);
const treasuryAddress = deployer.address;

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
  const ProtocolSettingsFactory = await ethers.getContractFactory('ProtocolSettings');
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(treasuryAddress);
  const settings = ProtocolSettings__factory.connect(ProtocolSettings.address, provider);
  console.log(`Deployed ProtocolSettings to ${settings.address}`);

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  const WandProtocol = await WandProtocolFactory.deploy(settings.address);
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);
  console.log(`Deployed WandProtocol to ${wandProtocol.address}`);

  const USBFactory = await ethers.getContractFactory('USB');
  const USB = await USBFactory.deploy(wandProtocol.address, "USB Token", "USB");
  const usbToken = USB__factory.connect(USB.address, provider);
  console.log(`Deployed $USB token to ${usbToken.address}`);

  const AssetPoolFactoryFactory = await ethers.getContractFactory('AssetPoolFactory');
  const AssetPoolFactory = await AssetPoolFactoryFactory.deploy(wandProtocol.address);
  const assetPoolFactory = AssetPoolFactory__factory.connect(AssetPoolFactory.address, provider);
  console.log(`Deployed AssetPoolFactory to ${assetPoolFactory.address} (${AssetPoolFactoryFactory.bytecode.length / 2} bytes)`);

  const AssetPoolCalculaorFactory = await ethers.getContractFactory('AssetPoolCalculator');
  const AssetPoolCalculator = await AssetPoolCalculaorFactory.deploy(usbToken.address);
  const assetPoolCalculaor = AssetPoolCalculator__factory.connect(AssetPoolCalculator.address, provider);
  console.log(`Deployed AssetPoolCalculator to ${assetPoolCalculaor.address}  (${AssetPoolCalculaorFactory.bytecode.length / 2} bytes)`);

  const InterestPoolFactoryFactory = await ethers.getContractFactory('InterestPoolFactory');
  const InterestPoolFactory = await InterestPoolFactoryFactory.deploy(wandProtocol.address);
  const interestPoolFactory = InterestPoolFactory__factory.connect(InterestPoolFactory.address, provider);
  console.log(`Deployed InterestPoolFactory to ${interestPoolFactory.address} (${InterestPoolFactoryFactory.bytecode.length / 2} bytes)`);

  let trans = await wandProtocol.connect(deployer).initialize(usbToken.address, assetPoolCalculaor.address, assetPoolFactory.address, interestPoolFactory.address);
  await trans.wait();
  console.log(`Initialized WandProtocol`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});