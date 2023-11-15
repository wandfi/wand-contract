import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  VaultFactory__factory,
  InterestPoolFactory__factory,
  AssetX__factory,
  Vault__factory,
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
const ethPriceFeedAddress = '0xDAf54D11EFdF5A2c3Fea091E2c0A556bCBb27cDC';

const wbtcAddress = '0xcAE964CfeEa795b8D545fBb0899e16A665218c65';
const wbtcPriceFeedAddress = '0xf44C8d847FB8a0D13501Fe3Df38Cc5E799a550C0'; // Mocked price feed for WBTC/USD on Goerli

const stethAddress = '0x18F37A1CA2D1fD5B104009fD288A947431203C78';
const stethPriceFeedAddress = '0x9B932019176Ab8E2cA55b6065ca37Dc284381f4E'; // Mocked price feed for stETH/USD on Goerli

const wandProtocolAddress = '0xA04b31AEC92CA3DD300B5a612eCd1A23673447eA';

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

/**
 * Deployment sequence:
 *  - Deploy ProtocolSettings
 *  - Deploy WandProtocol
 *  - Deploy USB
 *  - Deploy VaultCalculator
 *  - Deploy VaultFactory
 *  - Deploy InterestPoolFactory
 *  - Register USB/VaultCalculator/VaultFactory/InterestPoolFactory to WandProtocol
 * 
 *  - Create AssetPools
 *    - Deploy AssetX (WandProtocol.addVault)
 *    - Create Vault
 *    - Set Vault to AssetX
 *  - Create InterestPools
 *   - Deploy $USB InterestPool
 *   - Notifiy InterestPoolFactory
 */
async function main() {
  const wandProtocol = WandProtocol__factory.connect(wandProtocolAddress, provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);
  const vaultFactory = VaultFactory__factory.connect(await wandProtocol.vaultFactory(), provider);
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
  let trans = await wandProtocol.connect(deployer).addVault(
    ethAddress, ethPriceFeedAddress, ethxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [ethY, ethAART, ethAARS, ethAARC]
  );
  await trans.wait();

  const ethPoolAddress = await vaultFactory.getVaultAddress(ethAddress);
  const ethPool = Vault__factory.connect(ethPoolAddress, provider);
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
  trans = await wandProtocol.connect(deployer).addVault(
    wbtcAddress, wbtcPriceFeedAddress, wbtcxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [wbtcY, wbtcAART, wbtcAARS, wbtcAARC]
  );
  await trans.wait();
  const wbtcPoolAddress = await vaultFactory.getVaultAddress(wbtcAddress);
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
  trans = await wandProtocol.connect(deployer).addVault(
    stethAddress, stethPriceFeedAddress, stethxToken.address,
    [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC")],
    [stethY, stethAART, stethAARS, stethAARC]
  );
  await trans.wait();
  const stethPoolAddress = await vaultFactory.getVaultAddress(stethAddress);
  console.log(`Deployed $stETH asset pool to ${stethPoolAddress}`);

  trans = await stethxToken.connect(deployer).setAssetPool(stethPoolAddress);
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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});