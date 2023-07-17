import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { 
  ERC20Mock__factory,
  PriceFeedMock__factory,
  WandProtocol__factory,
  ProtocolSettings__factory,
  USB__factory,
  AssetPoolFactory__factory,
  InterestPoolFactory__factory
} from '../typechain';

const { provider } = ethers;

export const ONE_DAY_IN_SECS = 24 * 60 * 60;

export const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

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

  const WandProtocolFactory = await ethers.getContractFactory('WandProtocol');
  const WandProtocol = await WandProtocolFactory.deploy();
  const wandProtocol = WandProtocol__factory.connect(WandProtocol.address, provider);

  const settings = ProtocolSettings__factory.connect(await wandProtocol.settings(), provider);
  const usbToken = USB__factory.connect(await wandProtocol.usbToken(), provider);
  const assetPoolFactory = AssetPoolFactory__factory.connect(await wandProtocol.assetPoolFactory(), provider);
  const interestPoolFactory = InterestPoolFactory__factory.connect(await wandProtocol.interestPoolFactory(), provider);

  return { Alice, Bob, Caro, Dave, Ivy, erc20, wbtc, ethPriceFeed, wbtcPriceFeed, wandProtocol, settings, usbToken, assetPoolFactory, interestPoolFactory };
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