import dotenv from "dotenv";
import "@typechain/hardhat";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-etherscan";

import { HardhatUserConfig } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";

dotenv.config();

const chainIds = {
  hardhat: 31337,
  ganache: 1337,
  mainnet: 1,
  goerli: 5,
  sepolia: 11155111,
};

// Ensure that we have all the environment variables we need.
const privateKey: string = process.env.PRIVATE_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

function createTestnetConfig(network: keyof typeof chainIds): NetworkUserConfig {
  if (!infuraKey) {
    throw new Error("Missing INFURA_KEY");
  }

  let nodeUrl;
  switch (network) {
    case "mainnet":
      nodeUrl = `https://mainnet.infura.io/v3/${infuraKey}`;
      break;
    case "goerli":
      nodeUrl = `https://goerli.infura.io/v3/${infuraKey}`;
      break;
    case "sepolia":
      nodeUrl = `https://sepolia.infura.io/v3/${infuraKey}`;
      break;
  }

  return {
    chainId: chainIds[network],
    url: nodeUrl,
    accounts: [`${privateKey}`],
  };
}

const config: HardhatUserConfig = {
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          metadata: {
            bytecodeHash: "ipfs",
          },
          // You should disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: true,
            runs: 590,
          },
        },
      },
      {
        version: "0.4.18",
      },
      {
        version: "0.5.16",
      },
      {
        version: "0.6.6",
      },
    ],
  },
  abiExporter: {
    flat: true,
  },
  mocha: {
    parallel: false,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_KEY || "",
      goerli: process.env.ETHERSCAN_KEY || "",
      sepolia: process.env.ETHERSCAN_KEY || ""
    },
  },
};

if (privateKey) {
  config.networks = {
    mainnet: createTestnetConfig("mainnet"),
    goerli: createTestnetConfig("goerli"),
    sepolia: createTestnetConfig("sepolia"),
  };
}

config.networks = {
  ...config.networks,
  hardhat: {
    chainId: 1337,
    gas: "auto",
    gasPrice: "auto",
    allowUnlimitedContractSize: false,
  },
};

export default config;
