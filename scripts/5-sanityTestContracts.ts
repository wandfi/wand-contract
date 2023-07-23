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

const ethPoolAddress = '0x1e6537D3440372D5ff12bBE7C5e3B9191a5401EB';
const wbtcPoolAddress = '0x6Cab6c94e2086Dec7c1265fAb6f2D08F57e9D9Bf';

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const ethPool = AssetPool__factory.connect(ethPoolAddress, provider);
  const wbtcPool = AssetPool__factory.connect(wbtcPoolAddress, provider);

  // Mock $WBTC price to $30000
  const wbtcPriceFeed = PriceFeedMock__factory.connect(await wbtcPool.assetTokenPriceFeed(), provider);
  let trans = await wbtcPriceFeed.connect(deployer).mockPrice(BigNumber.from(30000).mul(BigNumber.from(10).pow(await wbtcPriceFeed.decimals())));
  await trans.wait();
  console.log(`Mocked $WBTC price to $30000`);

  // deposit 0.01 ETH to mint $USB
  await dumpAssetPoolState(ethPool);
  const ethAmount = ethers.utils.parseEther('0.01');
  trans = await ethPool.connect(deployer).mintUSB(ethAmount, {value: ethAmount});
  await trans.wait();
  console.log(`Deposited ${ethers.utils.formatEther(ethAmount)} ETH to mint $USB`);
  await dumpAssetPoolState(ethPool);

  // deposit 0.01 ETH to mint $ETHx
  trans = await ethPool.connect(deployer).mintXTokens(ethAmount, {value: ethAmount});
  await trans.wait();
  console.log(`Deposited ${ethers.utils.formatEther(ethAmount)} ETH to mint $ETHx`);
  await dumpAssetPoolState(ethPool);

  // deposit 0.01 $WBTC to mint $USB
  const wbtc = ERC20Mock__factory.connect(await wbtcPool.assetToken(), provider);
  const wbtcAmount = ethers.utils.parseUnits('0.01', await wbtc.decimals());
  trans = await wbtc.connect(deployer).mint(deployer.address, wbtcAmount);
  await trans.wait();
  console.log(`Minted ${ethers.utils.formatUnits(wbtcAmount, await wbtc.decimals())} $WBTC`);
  trans = await wbtc.connect(deployer).approve(wbtcPool.address, wbtcAmount);
  await trans.wait();
  console.log(`Approved ${ethers.utils.formatUnits(wbtcAmount, await wbtc.decimals())} $WBTC`);

  dumpAssetPoolState(wbtcPool);
  trans = await wbtcPool.connect(deployer).mintUSB(wbtcAmount);
  await trans.wait();
  console.log(`Deposited ${ethers.utils.formatUnits(wbtcAmount, await wbtc.decimals())} $WBTC to mint $USB`);
  dumpAssetPoolState(wbtcPool);
}

async function dumpAssetPoolState(assetPool: AssetPool) {
  const wandProtocol = WandProtocol__factory.connect(await assetPool.wandProtocol(), provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);

  const assetTokenERC20 = ERC20__factory.connect(await assetPool.assetToken(), provider);
  const assetSymbol = (await assetPool.assetToken() == nativeTokenAddress) ? 'ETH' : await assetTokenERC20.symbol();
  const assetPriceFeed = PriceFeedMock__factory.connect(await assetPool.assetTokenPriceFeed(), provider);
  const usbToken = USB__factory.connect(await assetPool.usbToken(), provider);
  const ethxToken = USB__factory.connect(await assetPool.xToken(), provider);

  console.log(`$${assetSymbol} Pool:`);
  console.log(`  M_${assetSymbol}: ${ethers.utils.formatUnits(await assetPool.getAssetTotalAmount(), 18)}`);
  console.log(`  P_${assetSymbol}: ${ethers.utils.formatUnits(await assetPriceFeed.latestPrice(), await assetPriceFeed.decimals())}`);
  console.log(`  M_USB: ${ethers.utils.formatUnits(await usbToken.totalSupply(), 18)}`);
  console.log(`  M_USB_${assetSymbol}: ${ethers.utils.formatUnits(await assetPool.usbTotalSupply(), 18)}`);
  console.log(`  M_${assetSymbol}x: ${ethers.utils.formatUnits(await ethxToken.totalSupply(), 18)}`);
  console.log(`  AAR: ${ethers.utils.formatUnits(await assetPool.AAR(), await assetPool.AARDecimals())}`);
  console.log(`  APY: ${ethers.utils.formatUnits(await assetPool.getParamValue(ethers.utils.formatBytes32String('Y')), await settings.decimals())}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});