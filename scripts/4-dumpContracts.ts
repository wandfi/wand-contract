import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  VaultFactory__factory,
  InterestPoolFactory__factory,
  Vault__factory,
  ERC20__factory,
  InterestPool__factory
} from '../typechain';

dotenv.config();

const infuraKey: string = process.env.INFURA_KEY || "";

const nativeTokenAddress = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

// Goerli
const provider = new ethers.providers.JsonRpcProvider(`https://goerli.infura.io/v3/${infuraKey}`);
const wandProtocolAddress = '0x5D55CCc45933A120b0962F3F230684EcFe6b66dC';

// mainnet
// const provider = new ethers.providers.JsonRpcProvider(`https://mainnet.infura.io/v3/${infuraKey}`);

async function main() {
  const wandProtocol = WandProtocol__factory.connect(wandProtocolAddress, provider);
  console.log(`WandProtocol: ${wandProtocol.address}`);
  console.log(`  $USB Token: ${await wandProtocol.usbToken()}`);
  console.log(`  ProtocolSettings: ${await wandProtocol.settings()}`);
  console.log(`  VaultCalculator: ${await wandProtocol.assetPoolCalculator()}`);
  console.log(`  VaultFactory: ${await wandProtocol.assetPoolFactory()}`);
  console.log(`  InterestPoolFactory: ${await wandProtocol.interestPoolFactory()}`);

  const assetPoolFactory = VaultFactory__factory.connect(await wandProtocol.assetPoolFactory(), provider);
  const assetTokens = await assetPoolFactory.assetTokens();
  console.log(`Asset Pools:`);
  for (let i = 0; i < assetTokens.length; i++) {
    const assetToken = assetTokens[i];
    const isETH = assetToken == nativeTokenAddress;
    const assetTokenERC20 = ERC20__factory.connect(assetToken, provider);
    const assetSymbol = isETH ? 'ETH' : await assetTokenERC20.symbol();
    const assetPoolAddress = await assetPoolFactory.getAssetPoolAddress(assetToken);
    const assetPool = Vault__factory.connect(assetPoolAddress, provider);
    const xToken = ERC20__factory.connect(await assetPool.xToken(), provider);
    console.log(`  $${assetSymbol} Pool: ${assetPoolAddress}`);
    console.log(`    Asset Token: ${assetToken}`);
    // console.log(`    Asset Pool: ${assetPoolAddress}`);
    console.log(`    Asset Price Oracle: ${await assetPool.assetTokenPriceFeed()}`);
    console.log(`    $${await xToken.symbol()} Token: ${xToken.address}`);
  }

  const interestPoolFactory = InterestPoolFactory__factory.connect(await wandProtocol.interestPoolFactory(), provider);
  const stakingTokens = await interestPoolFactory.stakingTokens();
  console.log(`Interest Pools:`);
  for (let i = 0; i < stakingTokens.length; i++) {
    const stakingTokenAddress = stakingTokens[i];
    const stakingToken = ERC20__factory.connect(stakingTokenAddress, provider);
    const interestPoolAddress = await interestPoolFactory.getInterestPoolAddress(stakingTokenAddress);
    const interestPool = InterestPool__factory.connect(interestPoolAddress, provider);
    const rewardTokens = await interestPool.rewardTokens();
    console.log(`  $${await stakingToken.symbol()} Pool: ${interestPoolAddress}`);
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