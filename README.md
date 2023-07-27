
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
WandProtocol: 0x523411921f0089E05A29897D600D0d64fA88f218
  $USB Token: 0xa703D24192BF8fe0eEfFd0626aD8cF6CE0D614E4
  ProtocolSettings: 0x535e4f99946Ac4d35c3DD5C182de6A3572B21Dae
  AssetPoolCalculator: 0xEa351B4Da7dc17A876562834129dBC805Cd3fC74
  AssetPoolFactory: 0xC89f209b4648706e115492fEBEA8D50A56f5fe87
  InterestPoolFactory: 0x6c61C525C1A732899871B4Ecbd375ED10a3bEa68
Asset Pools:
  $ETH Pool: 0xf33CBbA6F13172f40aab08cB547c822b4f06b8b8
    Asset Token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Price Oracle: 0x2f7DA0085A66599CEbC4d5fFc7d53d1C7711cf3e
    $ETHx Token: 0x6b96b5e42534884506ADF13e75dFB36F297532AA
  $WBTC Pool: 0x21A22e4bF6023650d98D87769aBC6bb1DD8ddd92
    Asset Token: 0x25d8D02457C9FAB1f0a3CD4Fa4B526Eb32f81114
    Asset Price Oracle: 0x1BDCF0d340cD22277A345Df4cfecc0C78EeBDEE8
    $WBTCx Token: 0xdFc58804d40da6F92360d8b2ADc907281616de41
  $stETH Pool: 0x54BCdED07DA80c0cB8664dA04D49Ba3D772df1E8
    Asset Token: 0x9d098c1d4d628013344ac8927c681b55bec49666
    Asset Price Oracle: 0x02BF5dd6C1BE5C5c2BD8168A9Eb6cB03F38D6E17
    $stETHx Token: 0xD6C885f3091D8d43E6C4e892c9aF1f10155bf056
Interest Pools:
  $USB Pool
    Staking Token: 0xa703D24192BF8fe0eEfFd0626aD8cF6CE0D614E4
    Reward Tokens:
      $ETHx: 0x6b96b5e42534884506ADF13e75dFB36F297532AA
      $WBTCx: 0xdFc58804d40da6F92360d8b2ADc907281616de41
      $stETHx: 0xD6C885f3091D8d43E6C4e892c9aF1f10155bf056
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.