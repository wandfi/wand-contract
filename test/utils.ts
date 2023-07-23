import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { 
  ERC20Mock__factory,
  PriceFeedMock__factory,
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  AssetPoolCalculaor__factory,
  AssetPoolFactory__factory,
  InterestPoolFactory__factory,
  AssetPool,
  ERC20__factory,
  AssetX__factory
} from '../typechain';

const { provider } = ethers;

export const ONE_DAY_IN_SECS = 24 * 60 * 60;

export const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

export const maxContractSize = 24576;

export async function deployContractsFixture() {
  const  [Alice, Bob, Caro, Dave, Ivy]  = await ethers.getSigners();

  const ERC20MockFactory = await ethers.getContractFactory('ERC20Mock');
  const ERC20Mock = await ERC20MockFactory.deploy("ERC20 Mock", "ERC20Mock");
  const erc20 = ERC20Mock__factory.connect(ERC20Mock.address, provider);

  const WBTC = await ERC20MockFactory.deploy("WBTC Token", "WBTC");
  const wbtc = ERC20Mock__factory.connect(WBTC.address, provider);

  const PriceFeedMockFactory = await ethers.getContractFactory('PriceFeedMock');
  const EthPriceFeedMock = await PriceFeedMockFactory.deploy("ETH", 6);
  const ethPriceFeed = PriceFeedMock__factory.connect(EthPriceFeedMock.address, provider);

  const WBTCPriceFeedMock = await PriceFeedMockFactory.deploy("WBTC", 6);
  const wbtcPriceFeed = PriceFeedMock__factory.connect(WBTCPriceFeedMock.address, provider);

  /**
   * Deployment sequence:
   *  - Deploy ProtocolSettings
   *  - Deploy WandProtocol
   *  - Deploy USB
   *  - Deploy AssetPoolCalculaor
   *  - Deploy AssetPoolFactory
   *  - Deploy InterestPoolFactory
   *  - Register USB/AssetPoolCalculaor/AssetPoolFactory/InterestPoolFactory to WandProtocol
   * 
   *  - Create AssetPools
   *    - Deploy AssetX (WandProtocol.addAssetPool)
   *    - Create AssetPool
   *    - Set AssetPool to AssetX
   *  - Create InterestPools
   *   - Deploy $USB InterestPool
   *   - Notifiy InterestPoolFactory
   */
  const ProtocolSettingsFactory = await ethers.getContractFactory('ProtocolSettings');
  expect(ProtocolSettingsFactory.bytecode.length / 2).lessThan(maxContractSize);
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(Alice.address);
  const settings = ProtocolSettings__factory.connect(ProtocolSettings.address, provider);

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  expect(WandProtocolFactory.bytecode.length / 2).lessThan(maxContractSize);
  const WandProtocol = await WandProtocolFactory.deploy(settings.address);
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);

  const USBFactory = await ethers.getContractFactory('USB');
  expect(USBFactory.bytecode.length / 2).lessThan(maxContractSize);
  const USB = await USBFactory.deploy(wandProtocol.address, "USB Token", "USB");
  const usbToken = USB__factory.connect(USB.address, provider);

  const AssetPoolFactoryFactory = await ethers.getContractFactory('AssetPoolFactory');
  expect(AssetPoolFactoryFactory.bytecode.length / 2).lessThan(maxContractSize);
  console.log(`AssetPoolFactory code size: ${AssetPoolFactoryFactory.bytecode.length / 2} bytes`);
  const AssetPoolFactory = await AssetPoolFactoryFactory.deploy(wandProtocol.address);
  const assetPoolFactory = AssetPoolFactory__factory.connect(AssetPoolFactory.address, provider);

  const AssetPool = await ethers.getContractFactory('AssetPool');
  expect(AssetPool.bytecode.length / 2).lessThan(maxContractSize);
  console.log(`AssetPool code size: ${AssetPool.bytecode.length / 2} bytes`);

  const AssetPoolCalculaorFactory = await ethers.getContractFactory('AssetPoolCalculaor');
  expect(AssetPoolCalculaorFactory.bytecode.length / 2).lessThan(maxContractSize);
  const AssetPoolCalculaor = await AssetPoolCalculaorFactory.deploy(usbToken.address);
  const assetPoolCalculaor = AssetPoolCalculaor__factory.connect(AssetPoolCalculaor.address, provider);

  const InterestPoolFactoryFactory = await ethers.getContractFactory('InterestPoolFactory');
  expect(InterestPoolFactoryFactory.bytecode.length / 2).lessThan(maxContractSize);
  console.log(`InterestPoolFactory code size: ${InterestPoolFactoryFactory.bytecode.length / 2} bytes`)
  const InterestPoolFactory = await InterestPoolFactoryFactory.deploy(wandProtocol.address);
  const interestPoolFactory = InterestPoolFactory__factory.connect(InterestPoolFactory.address, provider);

  let trans = await wandProtocol.connect(Alice).initialize(usbToken.address, assetPoolCalculaor.address, assetPoolFactory.address, interestPoolFactory.address);
  await trans.wait();

  return { Alice, Bob, Caro, Dave, Ivy, erc20, wbtc, ethPriceFeed, wbtcPriceFeed, wandProtocol, settings, usbToken, assetPoolFactory, interestPoolFactory };
}

export async function dumpAssetPoolState(assetPool: AssetPool) {
  const wandProtocol = WandProtocol__factory.connect(await assetPool.wandProtocol(), provider);
  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);

  const assetTokenERC20 = ERC20__factory.connect(await assetPool.assetToken(), provider);
  const assetSymbol = (await assetPool.assetToken() == nativeTokenAddress) ? 'ETH' : await assetTokenERC20.symbol();
  const assetPriceFeed = PriceFeedMock__factory.connect(await assetPool.assetTokenPriceFeed(), provider);
  const usbToken = USB__factory.connect(await assetPool.usbToken(), provider);
  const ethxToken = USB__factory.connect(await assetPool.xToken(), provider);

  console.log(`${assetSymbol} Pool:`);
  console.log(`  M_${assetSymbol}: ${ethers.utils.formatUnits(await assetPool.getAssetTotalAmount(), 18)}`);
  console.log(`  P_${assetSymbol}: ${ethers.utils.formatUnits(await assetPriceFeed.latestPrice(), await assetPriceFeed.decimals())}`);
  console.log(`  M_USB: ${ethers.utils.formatUnits(await usbToken.totalSupply(), 18)}`);
  console.log(`  M_USB_${assetSymbol}: ${ethers.utils.formatUnits(await assetPool.usbTotalSupply(), 18)}`);
  console.log(`  M_${assetSymbol}x: ${ethers.utils.formatUnits(await ethxToken.totalSupply(), 18)}`);
  console.log(`  AAR: ${ethers.utils.formatUnits(await assetPool.AAR(), await assetPool.AARDecimals())}`);
  // console.log(`  APY: ${ethers.utils.formatUnits(await assetPool.Y(), await settings.decimals())}`);
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