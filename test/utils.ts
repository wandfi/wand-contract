import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { 
  ERC20Mock__factory,
  PriceFeedMock__factory,
  WandProtocol__factory,
  ProtocolSettings__factory,
  Usb__factory,
  VaultFactory__factory,
  VaultCalculator__factory,
  Vault,
  ERC20__factory,
  RebasableERC20Mock__factory,
  Vault__factory,
  WETH9__factory,
  UniswapV2Factory__factory,
  UniswapV2Router02__factory,
  UniswapV2Pair__factory,
  PtyPool__factory
} from '../typechain';

const { provider } = ethers;

export const ONE_DAY_IN_SECS = 24 * 60 * 60;

export const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

export const enum PtyPoolType {
  RedeemByUsbBelowAARS = 0,
  MintUsbAboveAARU = 1
}

export const enum VaultPhase {
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
  const usbToken = Usb__factory.connect(Usb.address, provider);

  const VaultFactoryFactory = await ethers.getContractFactory('VaultFactory');
  expect(VaultFactoryFactory.bytecode.length / 2).lessThan(maxContractSize);
  console.log(`VaultFactory code size: ${VaultFactoryFactory.bytecode.length / 2} bytes`);
  const VaultFactory = await VaultFactoryFactory.deploy(wandProtocol.address);
  const vaultFactory = VaultFactory__factory.connect(VaultFactory.address, provider);

  const VaultCalculatorFactory = await ethers.getContractFactory('VaultCalculator');
  expect(VaultCalculatorFactory.bytecode.length / 2).lessThan(maxContractSize);
  const VaultCalculator = await VaultCalculatorFactory.deploy();
  const vaultCalculator = VaultCalculator__factory.connect(VaultCalculator.address, provider);

  const Vault = await ethers.getContractFactory('Vault');
  expect(Vault.bytecode.length / 2).lessThan(maxContractSize);
  console.log(`Vault code size: ${Vault.bytecode.length / 2} bytes`);

  // const LeveragedTokenFactory = await ethers.getContractFactory('LeveragedToken');
  // expect(LeveragedTokenFactory.bytecode.length / 2).lessThan(maxContractSize);
  // const ETHx = await LeveragedTokenFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
  // const ethx = LeveragedToken__factory.connect(ETHx.address, provider);

  let trans = await wandProtocol.connect(Alice).initialize(usbToken.address, vaultFactory.address);
  await trans.wait();

  return {
    Alice, Bob, Caro, Dave, Ivy,
    erc20, wbtc, stETH, usbToken,
    ethPriceFeed, wbtcPriceFeed,
    wandProtocol, settings, vaultFactory, vaultCalculator
  };
}

export async function deployUniswapUsbEthPool(signer: SignerWithAddress, usbAddress: string, initUsbAmount: BigNumber, initEthAmount: BigNumber) {
  const WETH9 = await ethers.getContractFactory('WETH9');
  const WETH9Contract = await WETH9.deploy();
  const weth = WETH9__factory.connect(WETH9Contract.address, provider);
  const UniswapV2Factory = await ethers.getContractFactory('UniswapV2Factory');
  const UniswapV2FactoryContract = await UniswapV2Factory.deploy(ethers.constants.AddressZero);
  const uniswapV2Factory = UniswapV2Factory__factory.connect(UniswapV2FactoryContract.address, provider);
  const UniswapV2Router02 = await ethers.getContractFactory('UniswapV2Router02');
  const UniswapV2Router02Contract = await UniswapV2Router02.deploy(uniswapV2Factory.address, weth.address);
  const uniswapV2Router02 = UniswapV2Router02__factory.connect(UniswapV2Router02Contract.address, provider);
  const usbToken = Usb__factory.connect(usbAddress, provider);
  const uniPairDeadline = (await time.latest()) + ONE_DAY_IN_SECS;
  await expect(usbToken.connect(signer).approve(uniswapV2Router02.address, initUsbAmount)).not.to.be.reverted;
  // Note: Update this value to the code hash used in test/UniswapV2Router02.sol:UniswapV2Library.pairFor()
  const UniswapV2Pair = await ethers.getContractFactory('UniswapV2Pair');
  console.log(`UniswapV2Pair bytecode hash: ${ethers.utils.keccak256(UniswapV2Pair.bytecode)}`);
  let trans = await uniswapV2Router02.connect(signer).addLiquidityETH(usbToken.address, initUsbAmount, initUsbAmount, initEthAmount, await signer.getAddress(), uniPairDeadline, {
    value: initEthAmount
  });
  await trans.wait();
  const uniPairAddress = await uniswapV2Factory.getPair(usbToken.address, weth.address);
  const uniLpToken = UniswapV2Pair__factory.connect(uniPairAddress, provider);
  return { weth, uniswapV2Factory, uniswapV2Router02, uniLpToken };
}

export async function dumpVaultState(vault: Vault) {
  const wandProtocol = WandProtocol__factory.connect(await vault.wandProtocol(), provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);

  const assetTokenERC20 = ERC20__factory.connect(await vault.assetToken(), provider);
  const assetSymbol = (await vault.assetToken() == nativeTokenAddress) ? 'ETH' : await assetTokenERC20.symbol();
  const priceInfo = await vault.assetTokenPrice();
  const usbToken = Usb__factory.connect(await vault.usbToken(), provider);
  const ethxToken = Usb__factory.connect(await vault.leveragedToken(), provider);

  const aar = await vault.AAR();
  const AAR = (aar == ethers.constants.MaxUint256) ? 'MaxUint256' : ethers.utils.formatUnits(aar, await vault.AARDecimals());

  console.log(`${assetSymbol} Vault:`);
  console.log(`  M_${assetSymbol}: ${ethers.utils.formatUnits(await vault.assetTotalAmount(), 18)}`);
  console.log(`  P_${assetSymbol}: ${ethers.utils.formatUnits(priceInfo[0], priceInfo[1])}`);
  console.log(`  M_USB: ${ethers.utils.formatUnits(await usbToken.totalSupply(), 18)}`);
  console.log(`  M_USB_${assetSymbol}: ${ethers.utils.formatUnits(await vault.usbTotalSupply(), 18)}`);
  console.log(`  M_${assetSymbol}x: ${ethers.utils.formatUnits(await ethxToken.totalSupply(), 18)}`);
  console.log(`  AAR: ${AAR}`);
  console.log(`  APY: ${ethers.utils.formatUnits(await vault.getParamValue(ethers.utils.formatBytes32String('Y')), await settings.decimals())}`);
  console.log(`  Phase: ${await vault.vaultPhase()}`);
}

export async function dumpContracts(wandProtocolAddress: string) {
  const wandProtocol = WandProtocol__factory.connect(wandProtocolAddress, provider);
  console.log(`WandProtocol: ${wandProtocol.address}`);
  console.log(`  $USB Token: ${await wandProtocol.usbToken()}`);
  console.log(`  ProtocolSettings: ${await wandProtocol.settings()}`);
  console.log(`  VaultFactory: ${await wandProtocol.vaultFactory()}`);

  const vaultFactory = VaultFactory__factory.connect(await wandProtocol.vaultFactory(), provider);
  const assetTokens = await vaultFactory.assetTokens();
  console.log(`Vaults:`);
  for (let i = 0; i < assetTokens.length; i++) {
    const assetToken = assetTokens[i];
    const isETH = assetToken == nativeTokenAddress;
    const assetTokenERC20 = ERC20__factory.connect(assetToken, provider);
    const assetSymbol = isETH ? 'ETH' : await assetTokenERC20.symbol();
    const vaultAddress = await vaultFactory.getVaultAddress(assetToken);
    const vault = Vault__factory.connect(vaultAddress, provider);
    const leveragedToken = ERC20__factory.connect(await vault.leveragedToken(), provider);
    const ptyPoolBelowAARS = PtyPool__factory.connect(await vault.ptyPoolBelowAARS(), provider);
    const ptyPoolAboveAARU = PtyPool__factory.connect(await vault.ptyPoolAboveAARU(), provider);
    console.log(`  $${assetSymbol} Vault`);
    console.log(`    Vault Address: ${vaultAddress}`);
    console.log(`    Asset Token: ${assetToken}`);
    console.log(`    Asset Price Feed: ${await vault.assetTokenPriceFeed()}`);
    console.log(`    $${await leveragedToken.symbol()} Token: ${leveragedToken.address}`);
    console.log(`    Pty Pool Below AARS: ${ptyPoolBelowAARS.address}`);
    console.log(`       Staking Token: ${await ptyPoolBelowAARS.stakingToken()}`);
    console.log(`       Target Token: ${await ptyPoolBelowAARS.targetToken()}`);
    console.log(`       Staking Yield Token: ${await ptyPoolBelowAARS.stakingYieldsToken()}`);
    console.log(`       Matching Yield Token: ${await ptyPoolBelowAARS.machingYieldsToken()}`);
    console.log(`    Pty Pool Above AARU: ${ptyPoolAboveAARU.address}`);
    console.log(`       Staking Token: ${await ptyPoolAboveAARU.stakingToken()}`);
    console.log(`       Target Token: ${await ptyPoolAboveAARU.targetToken()}`);
    console.log(`       Staking Yield Token: ${await ptyPoolAboveAARU.stakingYieldsToken()}`);
    console.log(`       Matching Yield Token: ${await ptyPoolAboveAARU.machingYieldsToken()}`);
  }
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