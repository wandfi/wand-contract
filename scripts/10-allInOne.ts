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
  USB__factory,
  VaultFactory__factory,
  VaultCalculator__factory,
  InterestPoolFactory__factory,
  AssetX__factory,
  Vault__factory,
  UsbInterestPool__factory,
  InterestPool__factory
} from '../typechain';

const { BigNumber } = ethers;

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
  // Step 1: Deploy Mocked ERC20 tokens and price feeds
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

  // Step 2: Deploy Wand Protocol core contracts
  const ProtocolSettingsFactory = await ethers.getContractFactory('ProtocolSettings');
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(treasuryAddress);
  const settings = ProtocolSettings__factory.connect(ProtocolSettings.address, provider);
  console.log(`Deployed ProtocolSettings to ${settings.address}`);

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  const WandProtocol = await WandProtocolFactory.deploy(settings.address);
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);
  console.log(`Deployed WandProtocol to ${wandProtocol.address}`);

  const USBFactory = await ethers.getContractFactory('Usb');
  const Usb = await USBFactory.deploy(wandProtocol.address, "USB Token", "Usb");
  const usbToken = USB__factory.connect(Usb.address, provider);
  console.log(`Deployed $USB token to ${usbToken.address}`);

  const AssetPoolFactoryFactory = await ethers.getContractFactory('VaultFactory');
  const VaultFactory = await AssetPoolFactoryFactory.deploy(wandProtocol.address);
  const vaultFactory = VaultFactory__factory.connect(VaultFactory.address, provider);
  console.log(`Deployed VaultFactory to ${vaultFactory.address} (${AssetPoolFactoryFactory.bytecode.length / 2} bytes)`);

  const AssetPoolCalculaorFactory = await ethers.getContractFactory('VaultCalculator');
  const VaultCalculator = await AssetPoolCalculaorFactory.deploy(usbToken.address);
  const assetPoolCalculaor = VaultCalculator__factory.connect(VaultCalculator.address, provider);
  console.log(`Deployed VaultCalculator to ${assetPoolCalculaor.address}  (${AssetPoolCalculaorFactory.bytecode.length / 2} bytes)`);

  const InterestPoolFactoryFactory = await ethers.getContractFactory('InterestPoolFactory');
  const InterestPoolFactory = await InterestPoolFactoryFactory.deploy(wandProtocol.address);
  const interestPoolFactory = InterestPoolFactory__factory.connect(InterestPoolFactory.address, provider);
  console.log(`Deployed InterestPoolFactory to ${interestPoolFactory.address} (${InterestPoolFactoryFactory.bytecode.length / 2} bytes)`);

  let trans = await wandProtocol.connect(deployer).initialize(usbToken.address, assetPoolCalculaor.address, vaultFactory.address, interestPoolFactory.address);
  await trans.wait();
  console.log(`Initialized WandProtocol`);

  // Step 3: Create asset pools
  // Create $ETHx token
  const AssetXFactory = await ethers.getContractFactory('LeveragedToken');
  const ETHx = await AssetXFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
  const ethxToken = AssetX__factory.connect(ETHx.address, provider);
  console.log(`Deployed $ETHx token to ${ethxToken.address}`);
  
  // Create ETH asset pool
  const ethAddress = nativeTokenAddress;
  const ethY = BigNumber.from(10).pow(await settings.decimals()).mul(365).div(10000);  // 3.65%
  const ethAART = BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100);  // 200%
  const ethAARS = BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100);  // 150%
  const ethAARC = BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100);  // 110%
  trans = await wandProtocol.connect(deployer).addVault(
    ethAddress, ethPriceFeed.address, ethxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [ethY, ethAART, ethAARS, ethAARC]
  );
  await trans.wait();

  const ethPoolAddress = await vaultFactory.getVaultAddress(ethAddress);
  const ethPool = Vault__factory.connect(ethPoolAddress, provider);
  console.log(`Deployed $ETH asset pool to ${ethPoolAddress}`);

  trans = await ethxToken.connect(deployer).setVault(ethPoolAddress);
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
  trans = await wandProtocol.connect(deployer).addVault(
    wbtc.address, wbtcPriceFeed.address, wbtcxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [wbtcY, wbtcAART, wbtcAARS, wbtcAARC]
  );
  await trans.wait();
  const wbtcPoolAddress = await vaultFactory.getVaultAddress(wbtc.address);
  console.log(`Deployed $WBTC asset pool to ${wbtcPoolAddress}`);

  trans = await wbtcxToken.connect(deployer).setVault(wbtcPoolAddress);
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
  trans = await wandProtocol.connect(deployer).addVault(
    stETH.address, stETHPriceFeed.address, stethxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [stethY, stethAART, stethAARS, stethAARC]
  );
  await trans.wait();
  const stethPoolAddress = await vaultFactory.getVaultAddress(stETH.address);
  console.log(`Deployed $stETH asset pool to ${stethPoolAddress}`);

  trans = await stethxToken.connect(deployer).setVault(stethPoolAddress);
  await trans.wait();
  console.log(`Connected $stETHx asset pool to $stETHx token`);

  // Add $USB InterestPool to $ETHx/$WBTCx/$stETHx whitelist
  trans = await ethxToken.connect(deployer).setWhitelistAddress(usbInterestPool.address, true);
  await trans.wait();
  console.log(`Added $USB interest pool to $ETHx whitelist`);
  trans = await wbtcxToken.connect(deployer).setWhitelistAddress(usbInterestPool.address, true);
  await trans.wait();
  console.log(`Added $USB interest pool to $WBTCx whitelist`);
  trans = await stethxToken.connect(deployer).setWhitelistAddress(usbInterestPool.address, true);
  await trans.wait();
  console.log(`Added $USB interest pool to $stETHx whitelist`);

  // Step 4: Add tester accounts
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

  // Dump contract addresses
  console.log(`WandProtocol: ${wandProtocol.address}`);
  console.log(`  $USB Token: ${await wandProtocol.usbToken()}`);
  console.log(`  ProtocolSettings: ${await wandProtocol.settings()}`);
  console.log(`  VaultCalculator: ${await wandProtocol.vaultCalculator()}`);
  console.log(`  VaultFactory: ${await wandProtocol.vaultFactory()}`);
  console.log(`  InterestPoolFactory: ${await wandProtocol.interestPoolFactory()}`);

  const assetTokens = await vaultFactory.assetTokens();
  console.log(`Asset Pools:`);
  for (let i = 0; i < assetTokens.length; i++) {
    const assetToken = assetTokens[i];
    const isETH = assetToken == nativeTokenAddress;
    const assetTokenERC20 = ERC20__factory.connect(assetToken, provider);
    const assetSymbol = isETH ? 'ETH' : await assetTokenERC20.symbol();
    const assetPoolAddress = await vaultFactory.getVaultAddress(assetToken);
    const assetPool = Vault__factory.connect(assetPoolAddress, provider);
    const leveragedToken = ERC20__factory.connect(await assetPool.leveragedToken(), provider);
    console.log(`  $${assetSymbol} Pool: ${assetPoolAddress}`);
    console.log(`    Asset Token: ${assetToken}`);
    // console.log(`    Asset Pool: ${assetPoolAddress}`);
    console.log(`    Asset Price Oracle: ${await assetPool.assetTokenPriceFeed()}`);
    console.log(`    $${await leveragedToken.symbol()} Token: ${leveragedToken.address}`);
  }

  const stakingTokens = await interestPoolFactory.stakingTokens();
  console.log(`Interest Pools:`);
  for (let i = 0; i < stakingTokens.length; i++) {
    const stakingTokenAddress = stakingTokens[i];
    const stakingToken = ERC20__factory.connect(stakingTokenAddress, provider);
    const interestPoolAddress = await interestPoolFactory.getInterestPoolAddress(stakingTokenAddress);
    const interestPool = InterestPool__factory.connect(interestPoolAddress, provider);
    const rewardTokens = await interestPool.rewardTokens();
    console.log(`  $${await stakingToken.symbol()} Pool`);
    console.log(`    Staking Token: ${stakingTokenAddress}`);
    console.log(`    Reward Tokens:`);
    for (let j = 0; j < rewardTokens.length; j++) {
      const rewardToken = rewardTokens[j];
      const rewardTokenERC20 = ERC20__factory.connect(rewardToken, provider);
      console.log(`      $${await rewardTokenERC20.symbol()}: ${rewardToken}`);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});