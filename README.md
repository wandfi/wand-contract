
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
$ hh run scripts/deployMockContracts.ts --network <goerli>

$ hh run scripts/deployContracts.ts --network <mainnet/goerli>

$ hh run scripts/addPools.ts --network <mainnet/goerli>

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
WandProtocol: 0xcfb2d127b8CB9D8cEc75E02674B2D6B931A87038
  $USB Token: 0x807D699594fD12D1dD8448B026EA1361b65D75c4
  ProtocolSettings: 0x32995491E0B6EcAebd51dfF140B0526041f83c57
  AssetPoolCalculator: 0xee8522a92af9773A2e34BFF44650B08E20bb3A9B
  AssetPoolFactory: 0x325B450F3f9eBc231948A5Dc2b8e9D0cc6B70b36
  InterestPoolFactory: 0x895eb3893068296c03915509B943d9Fe27D49b08
Asset Pools:
  $ETH Pool
    Asset Token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Pool: 0x9A46890924D1845aa6EFa724c63daa86DdDBdC1e
    Asset Price Feed: 0x05acAAe839d572D45109ef9EbbBB200AA7b0bB05
    $ETHx Token: 0xe562937ccD9D2088c20A4716C7376560CEDb3DD0
  $WBTC Pool
    Asset Token: 0x183c07F248e137E964E213925d0cfd0d3DCd8f1C
    Asset Pool: 0x48c097F86c30cA1029958ECbA238022eFce314e9
    Asset Price Feed: 0xCD1d9898453d49F947e518d1F2776CEd580095F2
    $WBTCx Token: 0x92a86AD8Da608c2D6f67D2C70A945dEAF5C1ea7A
Interest Pools:
  $USB Pool
    Staking Token: 0x807D699594fD12D1dD8448B026EA1361b65D75c4
    Reward Tokens:
      $ETHx: 0xe562937ccD9D2088c20A4716C7376560CEDb3DD0
      $WBTCx: 0x92a86AD8Da608c2D6f67D2C70A945dEAF5C1ea7A
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.