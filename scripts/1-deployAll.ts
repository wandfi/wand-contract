import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  PriceFeedMock__factory,
  ERC20__factory,
  ERC20Mock__factory,
  RebasableERC20Mock__factory,
  ProtocolSettings__factory,
  WandProtocol__factory,
  VaultCalculator__factory,
  Vault__factory,
  Usb__factory,
  LeveragedToken__factory,
  PtyPool__factory
} from '../typechain';
import { dumpContracts } from '../test/utils';

const { BigNumber } = ethers;

const enum PtyPoolType {
  RedeemByUsbBelowAARS = 0,
  MintUsbAboveAARU = 1
}

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const chainlinkETHUSD = "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e";
const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

const deployer = new ethers.Wallet(privateKey, provider);
const treasuryAddress = deployer.address;

const testers = [
  '0x956Cd653e87269b5984B8e1D2884E1C0b1b94442',
  '0xc97B447186c59A5Bb905cb193f15fC802eF3D543',
]

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {

  // Deploy Mocked ERC20 tokens and price feeds
  const ERC20MockFactory = await ethers.getContractFactory('ERC20Mock');
  const WBTC = await ERC20MockFactory.deploy('WBTC Token', 'WBTC');
  const wbtc = ERC20Mock__factory.connect(WBTC.address, provider);
  console.log(`Deployed Mocked WBTC token at ${wbtc.address}`);

  const RebasableERC20MockFactory = await ethers.getContractFactory('RebasableERC20Mock');
  const RebasableERC20Mock = await RebasableERC20MockFactory.deploy("Liquid staked Ether 2.0", "stETH");
  const stETH = RebasableERC20Mock__factory.connect(RebasableERC20Mock.address, provider);
  console.log(`Deployed Mocked stETH token at ${stETH.address}`);

  const CommonPriceFeedFactory = await ethers.getContractFactory('CommonPriceFeed');
  const commonPriceFeed = await CommonPriceFeedFactory.deploy('ETH', chainlinkETHUSD);
  const ethPriceFeed = PriceFeedMock__factory.connect(commonPriceFeed.address, provider);
  console.log(`Deployed Chainlink PriceFeed for ETH at ${ethPriceFeed.address}`);

  const PriceFeedMockFactory = await ethers.getContractFactory('PriceFeedMock');
  const WBTCPriceFeedMock = await PriceFeedMockFactory.deploy('WBTC', 6);
  const wbtcPriceFeed = PriceFeedMock__factory.connect(WBTCPriceFeedMock.address, provider);
  console.log(`Deployed Mocked PriceFeed for WBTC at ${wbtcPriceFeed.address}`);

  const PriceFeedMockForStETHFactory = await ethers.getContractFactory('PriceFeedMock');
  const stETHPriceFeedMock = await PriceFeedMockForStETHFactory.deploy('stETH', 6);
  const stETHPriceFeed = PriceFeedMock__factory.connect(stETHPriceFeedMock.address, provider);
  console.log(`Deployed Mocked PriceFeed for stETH at ${stETHPriceFeed.address}`);

  // Deploy Wand Protocol core contracts
  const ProtocolSettingsFactory = await ethers.getContractFactory('ProtocolSettings');
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(treasuryAddress);
  const settings = ProtocolSettings__factory.connect(ProtocolSettings.address, provider);
  console.log(`Deployed ProtocolSettings to ${settings.address}`);

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  const WandProtocol = await WandProtocolFactory.deploy(settings.address);
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);
  console.log(`Deployed WandProtocol to ${wandProtocol.address}`);

  const USBFactory = await ethers.getContractFactory('Usb');
  const Usb = await USBFactory.deploy(wandProtocol.address);
  const usbToken = Usb__factory.connect(Usb.address, provider);
  console.log(`Deployed $USB token to ${usbToken.address}`);

  let trans = await wandProtocol.connect(deployer).initialize(usbToken.address);
  await trans.wait();

  const VaultCalculatorFactory = await ethers.getContractFactory('VaultCalculator');
  const VaultCalculator = await VaultCalculatorFactory.deploy();
  const vaultCalculator = VaultCalculator__factory.connect(VaultCalculator.address, provider);
  console.log(`Deployed VaultCalculator to ${vaultCalculator.address} (${VaultCalculatorFactory.bytecode.length / 2} bytes)`);

  // Create $ETHx token
  const LeveragedTokenFactory = await ethers.getContractFactory('LeveragedToken');
  const ETHx = await LeveragedTokenFactory.deploy("ETHx Token", "ETHx");
  const ethx = LeveragedToken__factory.connect(ETHx.address, provider);
  console.log(`Deployed $ETHx token to ${ethx.address}`);
  
  // Create $ETH vault
  const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(2).div(100);  // 2.0%
  const ethAARU = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(130).div(100);  // 130%
  const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%

  const Vault = await ethers.getContractFactory('Vault');
  const ethVault = await Vault.deploy(wandProtocol.address, vaultCalculator.address, nativeTokenAddress, ethPriceFeed.address, ethx.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AARU"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
      [ethY, ethAARU, ethAART, ethAARS, ethAARC]);
  console.log(`Deployed $ETH vault to ${ethVault.address}`);

  trans = await wandProtocol.connect(deployer).addVault(ethVault.address);
  await trans.wait();
  console.log(`Connected $ETH vault to WandProtocol`);

  // Create PtyPools for $ETH vault
  const PtyPoolFactory = await ethers.getContractFactory('PtyPool');
  const EthVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(ethVault.address, PtyPoolType.RedeemByUsbBelowAARS, ethx.address, nativeTokenAddress);
  const ethVaultPtyPoolBelowAARS = PtyPool__factory.connect(EthVaultPtyPoolBelowAARS.address, provider);
  const EthVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(ethVault.address, PtyPoolType.MintUsbAboveAARU, nativeTokenAddress, ethx.address);
  const ethVaultPtyPoolAboveAARU = PtyPool__factory.connect(EthVaultPtyPoolAboveAARU.address, provider);
  trans = await ethVault.connect(deployer).setPtyPools(ethVaultPtyPoolBelowAARS.address, ethVaultPtyPoolAboveAARU.address);
  await trans.wait();
  console.log(`Connected PtyPools to $ETH vault`);

  // Create $stETH vault
  const stETHxToken = await LeveragedTokenFactory.deploy("stETHx Token", "stETHx");
  const stethx = LeveragedToken__factory.connect(stETHxToken.address, provider);
  const stETHY = BigNumber.from(10).pow(await settings.decimals()).mul(2).div(100);  // 2%
  const stETHAARU = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const stETHAART = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const stETHAARS = BigNumber.from(10).pow(await settings.decimals()).mul(130).div(100);  // 130%
  const stETHAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%

  const stethVault = await Vault.deploy(wandProtocol.address, vaultCalculator.address, stETH.address, stETHPriceFeed.address, stethx.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AARU"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
      [stETHY, stETHAARU, stETHAART, stETHAARS, stETHAARC]);
  console.log(`Deployed $stETH vault to ${stethVault.address}`);
  trans = await wandProtocol.connect(deployer).addVault(stethVault.address);
  await trans.wait();
  console.log(`Connected $stETH vault to WandProtocol`);

  // Connect $stethx with $stETH vault
  trans = await stethx.connect(deployer).setVault(stethVault.address);
  await trans.wait();
  console.log(`Connected $stETH vault to WandProtocol`);
  
  // Create PtyPools for $stETH vault
  const stETHVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(stethVault.address, PtyPoolType.RedeemByUsbBelowAARS, stethx.address, stETH.address);
  const stethVaultPtyPoolBelowAARS = PtyPool__factory.connect(stETHVaultPtyPoolBelowAARS.address, provider);
  const stETHVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(stethVault.address, PtyPoolType.MintUsbAboveAARU, stETH.address, stethx.address);
  const stethVaultPtyPoolAboveAARU = PtyPool__factory.connect(stETHVaultPtyPoolAboveAARU.address, provider);
  trans = await stethVault.connect(deployer).setPtyPools(stethVaultPtyPoolBelowAARS.address, stethVaultPtyPoolAboveAARU.address);
  await trans.wait();

  // Create $WBTC vault
  const WBTCx = await LeveragedTokenFactory.deploy("WBTCx Token", "WBTCx");
  const wbtcx = LeveragedToken__factory.connect(WBTCx.address, provider);
  const wbtcY = BigNumber.from(10).pow(await settings.decimals()).mul(30).div(1000);  // 3%
  const wbtcAARU = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const wbtcAART = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const wbtcAARS = BigNumber.from(10).pow(await settings.decimals()).mul(130).div(100);  // 130%
  const wbtcAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%

  const wbtcVault = await Vault.deploy(wandProtocol.address, vaultCalculator.address, wbtc.address, wbtcPriceFeed.address, wbtcx.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AARU"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
      [wbtcY, wbtcAARU, wbtcAART, wbtcAARS, wbtcAARC]);
  trans = await wandProtocol.connect(deployer).addVault(wbtcVault.address);
  await trans.wait();

  // Connect $WBTCx with WBTC vault
  trans = await wbtcx.connect(deployer).setVault(wbtcVault.address);
  await trans.wait();

  // Create PtyPools for $WBTC vault
  const WBTCVaultPtyPoolBelowAARS = await PtyPoolFactory.deploy(wbtcVault.address, PtyPoolType.RedeemByUsbBelowAARS, wbtcx.address, wbtc.address);
  const wbtcVaultPtyPoolBelowAARS = PtyPool__factory.connect(WBTCVaultPtyPoolBelowAARS.address, provider);
  const WBTCVaultPtyPoolAboveAARU = await PtyPoolFactory.deploy(wbtcVault.address, PtyPoolType.MintUsbAboveAARU, wbtc.address, wbtcx.address);
  const wbtcVaultPtyPoolAboveAARU = PtyPool__factory.connect(WBTCVaultPtyPoolAboveAARU.address, provider);
  trans = await wbtcVault.connect(deployer).setPtyPools(wbtcVaultPtyPoolBelowAARS.address, wbtcVaultPtyPoolAboveAARU.address);
  await trans.wait();
  
  // Add tester accounts
  for (let i = 0; i < _.size(testers); i++) {
    const tester = testers[i];
    const isAdmin = await wbtc.isAdmin(tester);
    if (isAdmin) {
      console.log(`$WBTC Token: ${tester} is already an admin`);
    }
    else {
      const trans = await wbtc.connect(deployer).setAdmin(tester, true);
      await trans.wait();
      console.log(`$WBTC Token: ${tester} is now an admin`);
    }
  }

  for (let i = 0; i < _.size(testers); i++) {
    const tester = testers[i];
    const isTester = await wbtcPriceFeed.isTester(tester);
    if (isTester) {
      console.log(`$WBTC Price Feed: ${tester} is already a tester`);
    }
    else {
      const trans = await wbtcPriceFeed.connect(deployer).setTester(tester, true);
      await trans.wait();
      console.log(`$WBTC Price Feed: ${tester} is now a tester`);
    }
  }

  for (let i = 0; i < _.size(testers); i++) {
    const tester = testers[i];
    const isAdmin = await stETH.isAdmin(tester);
    if (isAdmin) {
      console.log(`$stETH Token: ${tester} is already an admin`);
    }
    else {
      const trans = await stETH.connect(deployer).setAdmin(tester, true);
      await trans.wait();
      console.log(`$stETH Token: ${tester} is now an admin`);
    }
  }

  for (let i = 0; i < _.size(testers); i++) {
    const tester = testers[i];
    const isTester = await stETHPriceFeed.isTester(tester);
    if (isTester) {
      console.log(`$stETH Price Feed: ${tester} is already a tester`);
    }
    else {
      const trans = await stETHPriceFeed.connect(deployer).setTester(tester, true);
      await trans.wait();
      console.log(`$stETH Price Feed: ${tester} is now a tester`);
    }
  }

  // Step 5: Mock prices for $WBTC and $stETH
  // Mock $WBTC price to $30000
  trans = await wbtcPriceFeed.connect(deployer).mockPrice(BigNumber.from(30000).mul(BigNumber.from(10).pow(await wbtcPriceFeed.decimals())));
  await trans.wait();
  console.log(`Mocked $WBTC price to $30000`);

  // Mock $stETH price to $2000
  trans = await stETHPriceFeed.connect(deployer).mockPrice(BigNumber.from(2000).mul(BigNumber.from(10).pow(await stETHPriceFeed.decimals())));
  await trans.wait();
  console.log(`Mocked $stETH price to $2000`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});