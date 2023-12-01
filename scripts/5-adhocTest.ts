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

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const ethPool = Vault__factory.connect(ethVaultAddress, provider);

  // deposit 0.01 ETH to mint $USB
  await dumpVaultState(ethPool);
  const ethAmount = ethers.utils.parseEther('0.01');
  let trans = await ethPool.connect(deployer).mintPairsAtStabilityPhase(ethAmount, {value: ethAmount});
  await trans.wait();
  console.log(`Deposited ${ethers.utils.formatEther(ethAmount)} ETH to mint $USB`);
  await dumpVaultState(ethPool);
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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});