import dotenv from "dotenv";
import { ethers } from "hardhat";
dotenv.config();

async function main() {
    const VaultCalculatorFactory = await ethers.getContractFactory('VaultCalculator');
    const VaultCalculator = await VaultCalculatorFactory.deploy();
    console.log(`Deployed VaultCalculator to ${VaultCalculator.address} (${VaultCalculatorFactory.bytecode.length / 2} bytes)`);  
}
main().catch(console.error)