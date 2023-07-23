
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
WandProtocol: 0x99A966E3BB33080b6c8A752B932d51a1a0FEC30b
  $USB Token: 0x2f37F3D6a93AC7a0D5A5fF5924A0feF0F1E97096
  ProtocolSettings: 0x94A87d3F73Bbb7a65713b02D4A19e85aa456bd2a
  AssetPoolCalculator: 0x61688FAf46E0AF475e414271168fdACE571F8176
  AssetPoolFactory: 0x997d20e942691D7eD8DF29650791F9280bC86eBA
  InterestPoolFactory: 0x4262E7F6a202AadB242aB0889b7C503b02a498E5
Asset Pools:
  $ETH Pool
    Asset Token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Pool: 0x1e6537D3440372D5ff12bBE7C5e3B9191a5401EB
    Asset Price Feed: 0xf6E8f6233FbfBbA5d42547B7A94819c0afF91D8A
    $ETHx Token: 0x39D793f1B7BeDfE7a9834892CF1e6F438A741233
  $WBTC Pool
    Asset Token: 0xf8424b5359AAE2098eB9C8A51458b9D594B35096
    Asset Pool: 0x6Cab6c94e2086Dec7c1265fAb6f2D08F57e9D9Bf
    Asset Price Feed: 0x7286754f7523c2D84Ac9cdAb1F0f0e323f6745cc
    $WBTCx Token: 0x34801dFC736aCfe784408E9aa1F3186cdE9aCe26
Interest Pools:
  $USB Pool
    Staking Token: 0x2f37F3D6a93AC7a0D5A5fF5924A0feF0F1E97096
    Reward Tokens:
      $ETHx: 0x39D793f1B7BeDfE7a9834892CF1e6F438A741233
      $WBTCx: 0x34801dFC736aCfe784408E9aa1F3186cdE9aCe26
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.