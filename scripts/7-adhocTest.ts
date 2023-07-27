import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  AssetPool__factory,
  AssetPool,
  ERC20__factory,
  PriceFeedMock__factory,
  ERC20Mock__factory
} from '../typechain';

const { BigNumber } = ethers;

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const deployer = new ethers.Wallet(privateKey, provider);

const ethPoolAddress = '0x89BBE988c010846b935B07750A6Ff74A8c132534';

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const ethPool = AssetPool__factory.connect(ethPoolAddress, provider);

  // deposit 0.01 ETH to mint $USB
  await dumpAssetPoolState(ethPool);
  const ethAmount = ethers.utils.parseEther('0.01');
  let trans = await ethPool.connect(deployer).mintUSB(ethAmount, {value: ethAmount});
  await trans.wait();
  console.log(`Deposited ${ethers.utils.formatEther(ethAmount)} ETH to mint $USB`);
  await dumpAssetPoolState(ethPool);
}

async function dumpAssetPoolState(assetPool: AssetPool) {
  const wandProtocol = WandProtocol__factory.connect(await assetPool.wandProtocol(), provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);

  const assetTokenERC20 = ERC20__factory.connect(await assetPool.assetToken(), provider);
  const assetSymbol = (await assetPool.assetToken() == nativeTokenAddress) ? 'ETH' : await assetTokenERC20.symbol();
  const assetPriceFeed = PriceFeedMock__factory.connect(await assetPool.assetTokenPriceFeed(), provider);
  const usbToken = USB__factory.connect(await assetPool.usbToken(), provider);
  const ethxToken = USB__factory.connect(await assetPool.xToken(), provider);

  const aar = await assetPool.AAR();
  const AAR = (aar == ethers.constants.MaxUint256) ? 'MaxUint256' : ethers.utils.formatUnits(aar, await assetPool.AARDecimals());

  console.log(`$${assetSymbol} Pool:`);
  console.log(`  M_${assetSymbol}: ${ethers.utils.formatUnits(await assetPool.getAssetTotalAmount(), 18)}`);
  console.log(`  P_${assetSymbol}: ${ethers.utils.formatUnits(await assetPriceFeed.latestPrice(), await assetPriceFeed.decimals())}`);
  console.log(`  M_USB: ${ethers.utils.formatUnits(await usbToken.totalSupply(), 18)}`);
  console.log(`  M_USB_${assetSymbol}: ${ethers.utils.formatUnits(await assetPool.usbTotalSupply(), 18)}`);
  console.log(`  M_${assetSymbol}x: ${ethers.utils.formatUnits(await ethxToken.totalSupply(), 18)}`);
  console.log(`  AAR: ${AAR}`);
  console.log(`  r: ${ethers.utils.formatUnits(await assetPool.r(), await assetPool.AARDecimals())}`);
  console.log(`  R2: ${ethers.utils.formatUnits(await assetPool.R2(), await settings.decimals())}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});