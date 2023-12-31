import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  ProtocolSettings__factory,
  Usb__factory,
  Vault__factory,
  Vault,
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

const ethVaultAddress = '';
const wbtcVaultAddress = '';
const stethVaultAddress = '';

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const ethPool = Vault__factory.connect(ethVaultAddress, provider);
  const wbtcPool = Vault__factory.connect(wbtcVaultAddress, provider);
  const stethPool = Vault__factory.connect(stethVaultAddress, provider);

  // Mock $WBTC price to $30000
  const wbtcPriceFeed = PriceFeedMock__factory.connect(await wbtcPool.assetTokenPriceFeed(), provider);
  let trans = await wbtcPriceFeed.connect(deployer).mockPrice(BigNumber.from(30000).mul(BigNumber.from(10).pow(await wbtcPriceFeed.decimals())));
  await trans.wait();
  console.log(`Mocked $WBTC price to $30000`);

  // Mock $stETH price to $2000
  const stethPriceFeed = PriceFeedMock__factory.connect(await stethPool.assetTokenPriceFeed(), provider);
  trans = await stethPriceFeed.connect(deployer).mockPrice(BigNumber.from(2000).mul(BigNumber.from(10).pow(await stethPriceFeed.decimals())));
  await trans.wait();
  console.log(`Mocked $stETH price to $2000`);

  // // deposit 0.01 ETH to mint $ETHx
  // const ethAmount = ethers.utils.parseEther('0.01');
  // trans = await ethPool.connect(deployer).mintLeveragedTokens(ethAmount, {value: ethAmount});
  // await trans.wait();
  // console.log(`Deposited ${ethers.utils.formatEther(ethAmount)} ETH to mint $ETHx`);
  // await dumpVaultState(ethPool);

  // // deposit 0.01 ETH to mint $USB
  // await dumpVaultState(ethPool);
  // trans = await ethPool.connect(deployer).mintUSB(ethAmount, {value: ethAmount});
  // await trans.wait();
  // console.log(`Deposited ${ethers.utils.formatEther(ethAmount)} ETH to mint $USB`);
  // await dumpVaultState(ethPool);

  // // deposit 0.01 $WBTC to mint $USB
  // const wbtc = ERC20Mock__factory.connect(await wbtcPool.assetToken(), provider);
  // const wbtcAmount = ethers.utils.parseUnits('0.01', await wbtc.decimals());
  // trans = await wbtc.connect(deployer).mint(deployer.address, wbtcAmount);
  // await trans.wait();
  // console.log(`Minted ${ethers.utils.formatUnits(wbtcAmount, await wbtc.decimals())} $WBTC`);
  // trans = await wbtc.connect(deployer).approve(wbtcPool.address, wbtcAmount);
  // await trans.wait();
  // console.log(`Approved ${ethers.utils.formatUnits(wbtcAmount, await wbtc.decimals())} $WBTC`);

  // dumpVaultState(wbtcPool);
  // trans = await wbtcPool.connect(deployer).mintUSB(wbtcAmount);
  // await trans.wait();
  // console.log(`Deposited ${ethers.utils.formatUnits(wbtcAmount, await wbtc.decimals())} $WBTC to mint $USB`);
  // dumpVaultState(wbtcPool);
}

async function dumpVaultState(vault: Vault) {
  const wandProtocol = WandProtocol__factory.connect(await vault.wandProtocol(), provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);

  const assetTokenERC20 = ERC20__factory.connect(await vault.assetToken(), provider);
  const assetSymbol = (await vault.assetToken() == nativeTokenAddress) ? 'ETH' : await assetTokenERC20.symbol();
  const assetPriceFeed = PriceFeedMock__factory.connect(await vault.assetTokenPriceFeed(), provider);
  const usbToken = Usb__factory.connect(await vault.usbToken(), provider);
  const ethxToken = Usb__factory.connect(await vault.leveragedToken(), provider);

  const aar = await vault.AAR();
  const AAR = (aar == ethers.constants.MaxUint256) ? 'MaxUint256' : ethers.utils.formatUnits(aar, await vault.AARDecimals());

  console.log(`$${assetSymbol} Pool:`);
  console.log(`  M_${assetSymbol}: ${ethers.utils.formatUnits(await vault.assetTotalAmount(), 18)}`);
  console.log(`  P_${assetSymbol}: ${ethers.utils.formatUnits((await assetPriceFeed.latestPrice())[0], await assetPriceFeed.decimals())}`);
  console.log(`  M_USB: ${ethers.utils.formatUnits(await usbToken.totalSupply(), 18)}`);
  console.log(`  M_USB_${assetSymbol}: ${ethers.utils.formatUnits(await vault.usbTotalSupply(), 18)}`);
  console.log(`  M_${assetSymbol}x: ${ethers.utils.formatUnits(await ethxToken.totalSupply(), 18)}`);
  console.log(`  AAR: ${AAR}`);
  console.log(`  APY: ${ethers.utils.formatUnits(await vault.getParamValue(ethers.utils.formatBytes32String('Y')), await settings.decimals())}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});