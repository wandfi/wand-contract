import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";
import { BigNumberish } from "ethers";
import { ethers, network } from "hardhat";
import { deployContract } from "./hutils";
import { parseEther } from "ethers/lib/utils";

const { BigNumber } = ethers;

const enum PtyPoolType {
  RedeemByUsbBelowAARS = 0,
  MintUsbAboveAARU = 1,
}

dotenv.config();

const vaults = [
  {
    assetsToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    assetsSymbol: "ETH",
    assetsFeed: "0x694AA1769357215DE4FAC081bf1f309aDC325306",
  },
];
let deployer: SignerWithAddress;

async function deployValut(
  vault: (typeof vaults)[0],
  wandProtocalAddress: string,
  vaultCalculatorAddress: string,
  settingsDecimals: BigNumberish
) {
  // Deploy xToken
  const xTokenAddress = await deployContract(
    "LeveragedToken",
    [`${vault.assetsSymbol}x Token`, `${vault.assetsSymbol}x`],
    `${vault.assetsSymbol}x`
  );
  const xToken = await ethers.getContractAt("LeveragedToken", xTokenAddress);

  // CommonPriceFeed
  let assetsPriceFeedAddress: string;
  if (network.config.chainId == 1) {
    assetsPriceFeedAddress = await deployContract(
      "CommonPriceFeed",
      [vault.assetsSymbol, vault.assetsFeed],
      `${vault.assetsSymbol}_Feed`
    );
  } else {
    // mock price
    assetsPriceFeedAddress = await deployContract(
      "PriceFeedMock",
      [vault.assetsSymbol, BigNumber.from("18")],
      `${vault.assetsSymbol}_Feed_Mock`
    );
    const feedMock = await ethers.getContractAt("PriceFeedMock", assetsPriceFeedAddress);
    // setTester
    await feedMock
      .connect(deployer)
      .setTester(deployer.address, true)
      .then((tx) => tx.wait(1))
      .catch((e) => true);
    // mockPrice
    await feedMock
      .connect(deployer)
      .mockPrice(parseEther("2300"))
      .then((tx) => tx.wait(1))
      .catch((e) => true);
  }

  const Y = BigNumber.from(10).pow(settingsDecimals).mul(2).div(100); // 2.0%
  const AARU = BigNumber.from(10).pow(settingsDecimals).mul(200).div(100); // 200%
  const AART = BigNumber.from(10).pow(settingsDecimals).mul(150).div(100); // 150%
  const AARS = BigNumber.from(10).pow(settingsDecimals).mul(130).div(100); // 130%
  const AARC = BigNumber.from(10).pow(settingsDecimals).mul(110).div(100); // 110%
  const valutAddress = await deployContract(
    "Vault",
    [
      wandProtocalAddress,
      vaultCalculatorAddress,
      vault.assetsToken,
      assetsPriceFeedAddress,
      xTokenAddress,
      [
        ethers.utils.formatBytes32String("Y"),
        ethers.utils.formatBytes32String("AARU"),
        ethers.utils.formatBytes32String("AART"),
        ethers.utils.formatBytes32String("AARS"),
        ethers.utils.formatBytes32String("AARC"),
      ],
      [Y, AARU, AART, AARS, AARC],
    ],
    vault.assetsSymbol + "_Vault"
  );
  const Vault = await ethers.getContractAt("Vault", valutAddress);
  // below buy pool
  const belowPoolAddress = await deployContract(
    "PtyPool",
    [valutAddress, PtyPoolType.RedeemByUsbBelowAARS, xTokenAddress, vault.assetsToken],
    `${vault.assetsSymbol}_PtyPoolBelowAARS`
  );
  // above sell pool
  const abovePoolAddress = await deployContract(
    "PtyPool",
    [valutAddress, PtyPoolType.MintUsbAboveAARU, vault.assetsToken, xTokenAddress],
    `${vault.assetsSymbol}_PtyPoolAboveAARU`
  );

  // setPtyPools
  if ((await Vault.ptyPoolAboveAARU()) == "0x0000000000000000000000000000000000000000") {
    await Vault.connect(deployer)
      .setPtyPools(belowPoolAddress, abovePoolAddress)
      .then((tx) => tx.wait(1));
  }

  // xToken setVault
  if ((await xToken.vault()) == "0x0000000000000000000000000000000000000000")
    await xToken
      .connect(deployer)
      .setVault(valutAddress)
      .then((tx) => tx.wait(1));

  return valutAddress;
}

async function main() {
  const signers = await ethers.getSigners();
  deployer = signers[0];

  //  Deploy Wand Protocol core contracts
  const protocolSettingsAddress = await deployContract("ProtocolSettings", [deployer.address]);
  const settings = await ethers.getContractAt("ProtocolSettings", protocolSettingsAddress);

  // Deploy Wand Protocol
  const wandProtocalAddress = await deployContract("WandProtocol", [protocolSettingsAddress]);
  const wandProtocol = await ethers.getContractAt("WandProtocol", wandProtocalAddress);

  // Deploy Usb
  const usbAddress = await deployContract("Usb", [wandProtocalAddress]);
  const Usb = await ethers.getContractAt("Usb", usbAddress);
  // initProtocal usb
  if (!(await wandProtocol.initialized())) {
    await wandProtocol
      .connect(deployer)
      .initialize(Usb.address)
      .then((tx) => tx.wait(1));
  }
  console.log(`Initialized WandProtocol with $USB token`);

  // Deploy VaultCalculator
  const vaultCalculatorAddress = await deployContract("VaultCalculator", []);
  // const vaultCalculator = await ethers.getContractAt("VaultCalculator", usbAddress);

  const ethVaultAddress = await deployValut(
    vaults[0],
    wandProtocalAddress,
    vaultCalculatorAddress,
    await settings.decimals()
  );
  // protocal Add Vault
  if (!(await wandProtocol.isVault(ethVaultAddress)))
    await wandProtocol
      .connect(deployer)
      .addVault(ethVaultAddress)
      .then((tx) => tx.wait(1));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
