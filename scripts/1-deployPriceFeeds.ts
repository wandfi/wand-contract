import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  PriceFeedMock__factory,
  ERC20Mock__factory,
} from '../typechain';

dotenv.config();

const infuraKey: string = process.env.INFURA_KEY || "";

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const chainlinkETHUSD = "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e";

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const ERC20MockFactory = await ethers.getContractFactory('ERC20Mock');
  const WBTC = await ERC20MockFactory.deploy('WBTC Token', 'WBTC');
  const wbtc = ERC20Mock__factory.connect(WBTC.address, provider);
  console.log(`Deployed Mocked WBTC token at ${wbtc.address}`);

  const CommonPriceFeedFactory = await ethers.getContractFactory('CommonPriceFeed');
  const commonPriceFeed = await CommonPriceFeedFactory.deploy('ETH', chainlinkETHUSD);
  const ethPriceFeed = PriceFeedMock__factory.connect(commonPriceFeed.address, provider);
  console.log(`Deployed Chainlink PriceFeed for ETH at ${ethPriceFeed.address}`);

  const PriceFeedMockFactory = await ethers.getContractFactory('PriceFeedMock');
  const WBTCPriceFeedMock = await PriceFeedMockFactory.deploy('WBTC', 6);
  const wbtcPriceFeed = PriceFeedMock__factory.connect(WBTCPriceFeedMock.address, provider);
  console.log(`Deployed Mocked PriceFeed for WBTC at ${wbtcPriceFeed.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});