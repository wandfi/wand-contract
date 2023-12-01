import _ from 'lodash';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { 
  ERC20Mock__factory,
  PriceFeedMock__factory,
  WandProtocol__factory,
  ProtocolSettings__factory,
  Usb__factory,
  VaultCalculator__factory,
  Vault,
  ERC20__factory,
  RebasableERC20Mock__factory,
  Vault__factory,
  PtyPool__factory,
  LeveragedToken__factory
} from '../typechain';

const { provider } = ethers;

export const ONE_DAY_IN_SECS = 24 * 60 * 60;

export const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

export const enum PtyPoolType {
  RedeemByUsbBelowAARS = 0,
  MintUsbAboveAARU = 1
}

export enum VaultPhase {
  Empty = 0,
  Stability = 1,
  AdjustmentBelowAARS = 2,
  AdjustmentAboveAARU = 3
}

export const maxContractSize = 24576;

export async function deployContractsFixture() {
  const  [Alice, Bob, Caro, Dave, Ivy]  = await ethers.getSigners();

  const ERC20MockFactory = await ethers.getContractFactory('ERC20Mock');
  const ERC20Mock = await ERC20MockFactory.deploy("ERC20 Mock", "ERC20Mock");
  const erc20 = ERC20Mock__factory.connect(ERC20Mock.address, provider);

  const WBTC = await ERC20MockFactory.deploy("WBTC Token", "WBTC");
  const wbtc = ERC20Mock__factory.connect(WBTC.address, provider);

  const RebasableERC20MockFactory = await ethers.getContractFactory('RebasableERC20Mock');
  const RebasableERC20Mock = await RebasableERC20MockFactory.deploy("Liquid staked Ether 2.0", "stETH");
  const stETH = RebasableERC20Mock__factory.connect(RebasableERC20Mock.address, provider);

  const PriceFeedMockFactory = await ethers.getContractFactory('PriceFeedMock');
  const EthPriceFeedMock = await PriceFeedMockFactory.deploy("ETH", 6);
  const ethPriceFeed = PriceFeedMock__factory.connect(EthPriceFeedMock.address, provider);

  const stETHPriceFeedMock = await PriceFeedMockFactory.deploy("stETH", 6);
  const stethPriceFeed = PriceFeedMock__factory.connect(stETHPriceFeedMock.address, provider);

  const WBTCPriceFeedMock = await PriceFeedMockFactory.deploy("WBTC", 6);
  const wbtcPriceFeed = PriceFeedMock__factory.connect(WBTCPriceFeedMock.address, provider);

  /**
   * Deployment steps:
   *  - Deploy ProtocolSettings
   *  - Deploy WandProtocol
   *  - Deploy USB
   *  - Deploy VaultFactory
   *  - Register USB/VaultFactory to WandProtocol
   * 
   *  - Create Vaults
   *    - Deploy LeveragedToken
   *    - Create Vault
   *    - Set Vault to LeveragedToken
   *    - Create PtyPools
   *      - Deploy PtyPoolBelowAARS
   *      - Deploy PtyPoolAboveAARU
   *      - Set PtyPools to Vault
   */
  const ProtocolSettingsFactory = await ethers.getContractFactory('ProtocolSettings');
  expect(ProtocolSettingsFactory.bytecode.length / 2).lessThan(maxContractSize);
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(Ivy.address);
  const settings = ProtocolSettings__factory.connect(ProtocolSettings.address, provider);

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  expect(WandProtocolFactory.bytecode.length / 2).lessThan(maxContractSize);
  const WandProtocol = await WandProtocolFactory.deploy(settings.address);
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);

  const USBFactory = await ethers.getContractFactory('Usb');
  expect(USBFactory.bytecode.length / 2).lessThan(maxContractSize);
  const Usb = await USBFactory.deploy(wandProtocol.address);
  const usb = Usb__factory.connect(Usb.address, provider);

  const VaultCalculatorFactory = await ethers.getContractFactory('VaultCalculator');
  expect(VaultCalculatorFactory.bytecode.length / 2).lessThan(maxContractSize);
  const VaultCalculator = await VaultCalculatorFactory.deploy();
  const vaultCalculator = VaultCalculator__factory.connect(VaultCalculator.address, provider);

  const Vault = await ethers.getContractFactory('Vault');
  console.log(`Vault code size: ${Vault.bytecode.length / 2} bytes`);
  expect(Vault.bytecode.length / 2).lessThan(maxContractSize);

  // const LeveragedTokenFactory = await ethers.getContractFactory('LeveragedToken');
  // expect(LeveragedTokenFactory.bytecode.length / 2).lessThan(maxContractSize);
  // const ETHx = await LeveragedTokenFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
  // const ethx = LeveragedToken__factory.connect(ETHx.address, provider);

  let trans = await wandProtocol.connect(Alice).initialize(usb.address);
  await trans.wait();

  return {
    Alice, Bob, Caro, Dave, Ivy,
    erc20, wbtc, stETH, usb,
    ethPriceFeed, stethPriceFeed, wbtcPriceFeed,
    wandProtocol, settings, vaultCalculator
  };
}

export async function dumpVaultState(vault: Vault) {
  const wandProtocol = WandProtocol__factory.connect(await vault.wandProtocol(), provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);

  const assetTokenERC20 = ERC20__factory.connect(await vault.assetToken(), provider);
  const assetSymbol = (await vault.assetToken() == nativeTokenAddress) ? 'ETH' : await assetTokenERC20.symbol();
  const usbToken = Usb__factory.connect(await vault.usbToken(), provider);
  const ethxToken = Usb__factory.connect(await vault.leveragedToken(), provider);

  const state = await vault.vaultState();
  const priceInfo = await vault.assetTokenPrice();

  console.log(`${assetSymbol} Vault:`);
  console.log(`  M_${assetSymbol}: ${ethers.utils.formatUnits(await vault.assetTotalAmount(), 18)}`);
  console.log(`  P_${assetSymbol}: ${ethers.utils.formatUnits(priceInfo[0], priceInfo[1])}`);
  console.log(`  P_${assetSymbol}_i: ${ethers.utils.formatUnits(state.P_ETH_i, priceInfo[1])}`);
  console.log(`  M_USB: ${ethers.utils.formatUnits(await usbToken.totalSupply(), 18)}`);
  console.log(`  M_USB_${assetSymbol}: ${ethers.utils.formatUnits(await vault.usbTotalSupply(), 18)}`);
  console.log(`  M_${assetSymbol}x: ${ethers.utils.formatUnits(await ethxToken.totalSupply(), 18)}`);
  console.log(`  AAR: ${numberToPercent(_.toNumber(ethers.utils.formatUnits(state.aar.toString(), await settings.decimals())))}`);
  console.log(`  APY: ${numberToPercent(_.toNumber(ethers.utils.formatUnits(await vault.getParamValue(ethers.utils.formatBytes32String('Y')), await settings.decimals())))}`);
  console.log(`  Phase: ${VaultPhase[await vault.vaultPhase()]}`);
  console.log(`  AARBelowSafeLineTime: ${await vault.AARBelowSafeLineTime()}`);
  console.log(`  AARBelowCircuitBreakerLineTime: ${await vault.AARBelowCircuitBreakerLineTime()}`);
}

export async function dumpContracts(wandProtocolAddress: string) {
  const wandProtocol = WandProtocol__factory.connect(wandProtocolAddress, provider);
  console.log(`WandProtocol: ${wandProtocol.address}`);
  console.log(`  $USB Token: ${await wandProtocol.usbToken()}`);
  console.log(`  ProtocolSettings: ${await wandProtocol.settings()}`);
  console.log(`  Treasury: ${await ProtocolSettings__factory.connect(await wandProtocol.settings(), provider).treasury()}`);

  const assetTokens = await wandProtocol.assetTokens();
  console.log(`Vaults:`);
  for (let i = 0; i < assetTokens.length; i++) {
    const assetToken = assetTokens[i];
    const isETH = assetToken == nativeTokenAddress;
    const assetTokenERC20 = ERC20__factory.connect(assetToken, provider);
    const assetSymbol = isETH ? 'ETH' : await assetTokenERC20.symbol();
    const vaultAddress = await wandProtocol.getVaultAddress(assetToken);
    const vault = Vault__factory.connect(vaultAddress, provider);
    const leveragedToken = LeveragedToken__factory.connect(await vault.leveragedToken(), provider);
    const ptyPoolBelowAARS = PtyPool__factory.connect(await vault.ptyPoolBelowAARS(), provider);
    const ptyPoolAboveAARU = PtyPool__factory.connect(await vault.ptyPoolAboveAARU(), provider);
    console.log(`  $${assetSymbol} Vault`);
    console.log(`    Vault Address: ${vaultAddress}`);
    console.log(`    Asset Token (${await getTokenSymbol(assetToken)}): ${assetToken}`);
    console.log(`    Asset Price Feed: ${await vault.assetTokenPriceFeed()}`);
    console.log(`    $${await leveragedToken.symbol()} Token: ${leveragedToken.address}`);
    console.log(`       Vault: ${await leveragedToken.vault()}`);
    console.log(`    Pty Pool Below AARS: ${ptyPoolBelowAARS.address}`);
    console.log(`       Staking Token (${await getTokenSymbol(await ptyPoolBelowAARS.stakingToken())}): ${await ptyPoolBelowAARS.stakingToken()}`);
    console.log(`       Target Token (${await getTokenSymbol(await ptyPoolBelowAARS.targetToken())}): ${await ptyPoolBelowAARS.targetToken()}`);
    console.log(`       Staking Yield Token (${await getTokenSymbol(await ptyPoolBelowAARS.stakingYieldsToken())}): ${await ptyPoolBelowAARS.stakingYieldsToken()}`);
    console.log(`       Matching Yield Token (${await getTokenSymbol(await ptyPoolBelowAARS.machingYieldsToken())}): ${await ptyPoolBelowAARS.machingYieldsToken()}`);
    console.log(`    Pty Pool Above AARU: ${ptyPoolAboveAARU.address}`);
    console.log(`       Staking Token (${await getTokenSymbol(await ptyPoolAboveAARU.stakingToken())}): ${await ptyPoolAboveAARU.stakingToken()}`);
    console.log(`       Target Token (${await getTokenSymbol(await ptyPoolAboveAARU.targetToken())}): ${await ptyPoolAboveAARU.targetToken()}`);
    console.log(`       Staking Yield Token (${await getTokenSymbol(await ptyPoolAboveAARU.stakingYieldsToken())}): ${await ptyPoolAboveAARU.stakingYieldsToken()}`);
    console.log(`       Matching Yield Token (${await getTokenSymbol(await ptyPoolAboveAARU.machingYieldsToken())}): ${await ptyPoolAboveAARU.machingYieldsToken()}`);
  }
}

async function getTokenSymbol(tokenAddr: string) {
  if (tokenAddr == nativeTokenAddress) {
    return '$ETH';
  }
  const erc20 = ERC20__factory.connect(tokenAddr, provider);
  return `$${await erc20.symbol()}`;
}

export function expandTo18Decimals(n: number) {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18));
}

// ensure result is within .01%
export function expectBigNumberEquals(expected: BigNumber, actual: BigNumber) {
  const equals = expected.sub(actual).abs().lte(expected.div(10000));
  if (!equals) {
    console.log(`BigNumber does not equal. expected: ${expected.toString()}, actual: ${actual.toString()}`);
  }
  expect(equals).to.be.true;
}

export function numberToPercent(num: number) {
  return new Intl.NumberFormat('default', {
    style: 'percent',
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  }).format(num);
}