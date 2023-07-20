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

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const ERC20MockFactory = await ethers.getContractFactory('ERC20Mock');
  const WBTC = await ERC20MockFactory.deploy("WBTC Token", "WBTC");
  const wbtc = ERC20Mock__factory.connect(WBTC.address, provider);
  console.log(`Deployed Mocked WBTC token at ${wbtc.address}`);

  const PriceFeedMockFactory = await ethers.getContractFactory('PriceFeedMock');
  const EthPriceFeedMock = await PriceFeedMockFactory.deploy("ETH", 6);
  const ethPriceFeed = PriceFeedMock__factory.connect(EthPriceFeedMock.address, provider);
  console.log(`Deployed Mocked PriceFeed for ETH at ${ethPriceFeed.address}`);

  const WBTCPriceFeedMock = await PriceFeedMockFactory.deploy("WBTC", 6);
  const wbtcPriceFeed = PriceFeedMock__factory.connect(WBTCPriceFeedMock.address, provider);
  console.log(`Deployed Mocked PriceFeed for WBTC at ${wbtcPriceFeed.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});