import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  PriceFeedMock__factory,
  ERC20Mock__factory
} from '../typechain';

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const deployer = new ethers.Wallet(privateKey, provider);

const wbtcAddress = '0xcAE964CfeEa795b8D545fBb0899e16A665218c65';
const wbtcPriceFeedAddress = '0xf44C8d847FB8a0D13501Fe3Df38Cc5E799a550C0'; 

const stethAddress = '0x18F37A1CA2D1fD5B104009fD288A947431203C78';
const stethPriceFeedAddress = '0x9B932019176Ab8E2cA55b6065ca37Dc284381f4E';

const testers = [
  '0x956Cd653e87269b5984B8e1D2884E1C0b1b94442',
  '0xc97B447186c59A5Bb905cb193f15fC802eF3D543',
]

async function main() {
  const wbtc = ERC20Mock__factory.connect(wbtcAddress, provider);
  const steth = ERC20Mock__factory.connect(stethAddress, provider);
  const wbtcPriceFeed = PriceFeedMock__factory.connect(wbtcPriceFeedAddress, provider);
  const stethPriceFeed = PriceFeedMock__factory.connect(stethPriceFeedAddress, provider);

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
    const isAdmin = await steth.isAdmin(tester);
    if (isAdmin) {
      console.log(`$stETH Token: ${tester} is already an admin`);
    }
    else {
      const trans = await steth.connect(deployer).setAdmin(tester, true);
      await trans.wait();
      console.log(`$stETH Token: ${tester} is now an admin`);
    }
  }

  for (let i = 0; i < _.size(testers); i++) {
    const tester = testers[i];
    const isTester = await stethPriceFeed.isTester(tester);
    if (isTester) {
      console.log(`$stETH Price Feed: ${tester} is already a tester`);
    }
    else {
      const trans = await stethPriceFeed.connect(deployer).setTester(tester, true);
      await trans.wait();
      console.log(`$stETH Price Feed: ${tester} is now a tester`);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});