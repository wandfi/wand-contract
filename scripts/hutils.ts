import { readFileSync, writeFileSync, openSync, existsSync, closeSync } from "fs";
import { ethers, network, run } from "hardhat";
const path = "./json/" + network.name + ".json";
if (!existsSync(path)) {
  const num = openSync(path, "w");
  closeSync(num);
}

export type DeployedVerifyJson = { [k: string]: any };
export function getJson(): DeployedVerifyJson {
  const json = readFileSync(path, "utf-8");
  const dto = JSON.parse(json || "{}") as any;
  return dto;
}

export function writeJson(dto: DeployedVerifyJson) {
  writeFileSync(path, JSON.stringify(dto, undefined, 2));
}

export function saveAny(dto: DeployedVerifyJson) {
  const old = getJson() || {};
  const nDto = { ...old, ...dto };
  writeJson(nDto);
}

export async function deployContract(name: string, args: any[], saveName?: string) {
  const showName = saveName || name;
  const old = getJson()[showName];
  const Factory = await ethers.getContractFactory(name);
  if (!old?.address) {
    const Contract = await Factory.deploy(...args);
    await Contract.deployed();

    saveAny({ [showName]: { address: Contract.address, args } });
    console.info("deployed:", showName, Contract.address);
    return Contract.address;
  } else {
    console.info("allredy deployed:", showName, old.address);
    return old.address as string;
  }
}

export async function deployUseCreate2(name: string, salt: string, typeargs: any[] = [], saveName?: string) {
  const showName = saveName || name;
  const AddCreate2 = "0x0000000000FFe8B47B3e2130213B802212439497";
  const immutableCreate2 = await ethers.getContractAt("ImmutableCreate2FactoryInterface", AddCreate2);
  let initCode = "";
  const factory = await ethers.getContractFactory(name);
  if (typeargs.length) {
    const encodeArgs = ethers.utils.defaultAbiCoder.encode(
      typeargs.slice(0, typeargs.length / 2),
      typeargs.slice(typeargs.length / 2)
    );
    initCode = ethers.utils.solidityPack(["bytes", "bytes"], [factory.bytecode, encodeArgs]);
  } else {
    initCode = factory.bytecode;
  }
  if (!initCode) throw "Error";
  const address = ethers.utils.getCreate2Address(
    AddCreate2,
    salt,
    ethers.utils.keccak256(ethers.utils.hexlify(initCode))
  );
  const deployed = await immutableCreate2.hasBeenDeployed(address);
  if (deployed) {
    console.info("already-deployd:", showName, address);
  } else {
    const tx = await immutableCreate2.safeCreate2(salt, initCode);
    await tx.wait(1);
    console.info("deplyed:", showName, address);
  }
  saveAny({ [showName]: { address, salt, typeargs } });
  return address;
}

export async function verfiy(key: string) {
  const json = getJson() || {};
  const item = json[key];
  if (item.args && item.address) {
    await run("verify:verify", {
      address: item.address,
      constructorArguments: item.args,
    }).catch((error) => {
      console.error(error);
    });
  }
}

export async function verifyAll() {
  const json = getJson() || {};
  Object.keys(json);
  for (const key in json) {
    await verfiy(key);
  }
}
