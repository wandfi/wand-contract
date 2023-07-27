
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
WandProtocol: 0xA04b31AEC92CA3DD300B5a612eCd1A23673447eA
  $USB Token: 0x3BC8EDA06555c061Ab5363Fc2b642C977BDcD6a6
  ProtocolSettings: 0x69C017F4e7F8eBf96866FE5AAb90096208e0fb60
  AssetPoolCalculator: 0xE69b03c90Db9E5CF66D2B4b46e4486725fdD14d6
  AssetPoolFactory: 0xdb2F1cC0e94c08D7282865E0d54ec5ce5c975e73
  InterestPoolFactory: 0xf60135e29A76c18c934ddb9fc0D85d7671694611
Asset Pools:
  $ETH Pool: 0x89BBE988c010846b935B07750A6Ff74A8c132534
    Asset Token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Price Oracle: 0xDAf54D11EFdF5A2c3Fea091E2c0A556bCBb27cDC
    $ETHx Token: 0x1aDf0bb122BAf003cdeBBe4B9041da20117e24b6
  $WBTC Pool: 0x383ba522b4B515f17CA5fd46BA82b9598A02c309
    Asset Token: 0xcAE964CfeEa795b8D545fBb0899e16A665218c65
    Asset Price Oracle: 0xf44C8d847FB8a0D13501Fe3Df38Cc5E799a550C0
    $WBTCx Token: 0x586fA472aa706bcB6e0b1fDAeDFac8799F7a0e51
  $stETH Pool: 0xDD92644966a1B495DFD0225313a9294501e83034
    Asset Token: 0x18F37A1CA2D1fD5B104009fD288A947431203C78
    Asset Price Oracle: 0x9B932019176Ab8E2cA55b6065ca37Dc284381f4E
    $stETHx Token: 0x55963a781f8484eF559bE020217b9546e305F713
Interest Pools:
  $USB Pool
    Staking Token: 0x3BC8EDA06555c061Ab5363Fc2b642C977BDcD6a6
    Reward Tokens:
      $ETHx: 0x1aDf0bb122BAf003cdeBBe4B9041da20117e24b6
      $WBTCx: 0x586fA472aa706bcB6e0b1fDAeDFac8799F7a0e51
      $stETHx: 0x55963a781f8484eF559bE020217b9546e305F713
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.