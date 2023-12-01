import * as _ from 'lodash';
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  WandProtocol__factory,
  Vault__factory,
  ERC20__factory,
  ProtocolSettings__factory,
  PtyPool__factory,
  LeveragedToken__factory
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

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});