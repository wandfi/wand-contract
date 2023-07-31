
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
WandProtocol: 0x5B9b0E0aB289c0dB485c79a5Ff622Db2D0Ecc66c
  $USB Token: 0x294CC2d08Cda68323aC831eF04E1C5e65a54857e
  ProtocolSettings: 0x3CD55aE3D217a884C0D2447B6C89AcD31aCf6f0B
  AssetPoolCalculator: 0x137f342A7216b4C6fa8d928CefA17826A041A9Dc
  AssetPoolFactory: 0x5E6c7C32fcEbfB7b655B3612F66f615533FAbaFD
  InterestPoolFactory: 0x18fe3F7629418725ADDBb91774C85683AF2b0F6F
Asset Pools:
  $ETH Pool: 0xb6680489383BcC5Bd971dDb911CAF3c8f8d98521
    Asset Token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Price Oracle: 0xc3d7557A4A956100ddd0b9880107C647a9bBeC0c
    $ETHx Token: 0x866b8ab4BAFa76E81944c5882425006476357574
  $WBTC Pool: 0x809c9A05Bd260949c6335479D6bf5f5cA5c101A7
    Asset Token: 0x389258b50E57402Ff596b35c7e2912a9E13cff7C
    Asset Price Oracle: 0x2563eb59Ca33A99B142E46Ac006cBa4D418f93EC
    $WBTCx Token: 0x94d68EECFF32d41aa0c928266722a40b2EE25F8a
  $stETH Pool: 0xF77D182ab25323693d20E791DBCed751B3505BAe
    Asset Token: 0x8b3aB92c92E1321e7dCCedCcE89037A726059da9
    Asset Price Oracle: 0xb37027447975F4045cEC3F7C0c53f22Ede1D5F91
    $stETHx Token: 0x9EAfd67C19A02eDf2A8f7C6B67DcA7DbE9F869d5
Interest Pools:
  $USB Pool
    Staking Token: 0x294CC2d08Cda68323aC831eF04E1C5e65a54857e
    Reward Tokens:
      $ETHx: 0x866b8ab4BAFa76E81944c5882425006476357574
      $WBTCx: 0x94d68EECFF32d41aa0c928266722a40b2EE25F8a
      $stETHx: 0x9EAfd67C19A02eDf2A8f7C6B67DcA7DbE9F869d5
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.