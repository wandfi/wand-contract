
## Getting Started

### Compile Contracts

```sh
$ yarn
$ hh compile
```

### Deploy Contracts

#### Prepare `.env` 

With same keys to `.env-example`

```sh
$ hh run scripts/1-deployPriceFeeds.ts --network <goerli>

$ hh run scripts/2-deployContracts.ts --network <mainnet/goerli>

$ hh run scripts/3-addPools.ts --network <mainnet/goerli>

# Etherscan verify
$ hh verify --network <mainnet/goerli> <address>

```

### Run Test Cases

```sh
$ hh test
# To run test cases of a test file:
$ hh test ./test/xxx.ts
```

## Contract Addresses

### Goerli

```
WandProtocol: 0x5D55CCc45933A120b0962F3F230684EcFe6b66dC
  $USB Token: 0x9EAFdB7111628129fFee1af04593858E09797cD6
  ProtocolSettings: 0x2693B9C17d42D1509A29452a870C3D8EAA2A6dfb
  AssetPoolCalculator: 0x10C51cE12Fb4B48201946EE9EECcAd83C4cbd8FC
  AssetPoolFactory: 0x3eeF41e9336e198c502eCEe7Bf6a85A410A1Ed54
  InterestPoolFactory: 0xd21426442aD90Da0E0E15f3388F10b261DB3c988
Asset Pools:
  $ETH Pool: 0x40b44716085d8f4f53F97081f561E8B669c65aB2
    Asset Token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Price Oracle: 0x73827BEA9e8EF23721132a340e8F8398eDd45910
    $ETHx Token: 0xF73855634cE15e2Deab0111D37ccAF0aeA737C84
  $WBTC Pool: 0xF98Bdb67Cb77525B96e66333f9c2d078f2876689
    Asset Token: 0xdc413E2AAc07F1B42595AcB66ca043563ff08654
    Asset Price Oracle: 0x22E437613D7Ca6EF59479DB8275a10d539024eae
    $WBTCx Token: 0x63B98824628ABf8c326C66e75791f6A951a5e273
  $stETH Pool: 0x8647bc05eeb0Cd66E1Bf90E471CBc503D2E9A30D
    Asset Token: 0x3426EDF191ca2a6C7138d6e88DEc5C3F39E57fE6
    Asset Price Oracle: 0x1e1d8342AA7D01745a89Cd85A671A19773D57b01
    $stETHx Token: 0xD7011496029108D6BBD6B0D1DD363Ff4Efdb8283
Interest Pools:
  $USB Pool
    Staking Token: 0x9EAFdB7111628129fFee1af04593858E09797cD6
    Reward Tokens:
      $ETHx: 0xF73855634cE15e2Deab0111D37ccAF0aeA737C84
      $WBTCx: 0x63B98824628ABf8c326C66e75791f6A951a5e273
      $stETHx: 0xD7011496029108D6BBD6B0D1DD363Ff4Efdb8283
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.