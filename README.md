
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
$ hh run scripts/1-deployAll.ts --network <mainnet/goerli>

# Etherscan verify
$ hh verify --network <mainnet/goerli> <address>

```

### Run Test Cases

```sh
$ hh test
# To run test cases of a test file:
$ hh test ./test/xxx.ts
```

**To run forge tests**

```sh
$ forge test
```

## Contract Addresses

### Goerli

```
WandProtocol: 0xdc1e86Abd837d693808a0FDAF6fd7cD5e449af54
  $USB Token: 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
  ProtocolSettings: 0x28443C5637D7688Dc94baEc849dF44Ed23A1Ce16
  Treasury: 0x1b28D2fBF84E9D13e89fCCc296f808DC12FBeF01
  VaultCaculator: 0xCda6DcF2D6f7f670C1e37CDd514546210038E310
Vaults:
  $ETH Vault
    Vault Address: 0x4C18f7CE2891Ba5F04558C0c205c4d2c7b34BDaB
    Asset Token ($ETH): 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Asset Price Feed: 0x9B5A61e9f8A3e35F50887c3Ce5c42A346e85C58e
    $ETHx Token: 0xEE400AA492Ad3A1D940cdb2756adf6E20B010923
       Vault: 0x4C18f7CE2891Ba5F04558C0c205c4d2c7b34BDaB
    Pty Pool Below AARS: 0x017049bE6F63E9C0875C60a22Db4F798056ccA7B
       Staking Token ($USB): 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
       Target Token ($ETH): 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
       Staking Yield Token ($ETHx): 0xEE400AA492Ad3A1D940cdb2756adf6E20B010923
       Matching Yield Token ($ETH): 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    Pty Pool Above AARU: 0x0A4D44522914eC8D11670f022634F1943C8c1cF2
       Staking Token ($ETH): 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
       Target Token ($USB): 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
       Staking Yield Token ($ETH): 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
       Matching Yield Token ($ETHx): 0xEE400AA492Ad3A1D940cdb2756adf6E20B010923
  $stETH Vault
    Vault Address: 0x6877A4ECbAeE1607908Ffe772859C2C7Ad0d056A
    Asset Token ($stETH): 0x88D10dBf2A4dc90514D05A60595c26098c3393D2
    Asset Price Feed: 0xDd6245a1cE2cc5DE91eA4000f790bbCBED572dCF
    $stETHx Token: 0xBc4647B83448b8Ed4b1730A0B3D10f1F67924d14
       Vault: 0x6877A4ECbAeE1607908Ffe772859C2C7Ad0d056A
    Pty Pool Below AARS: 0x43A00D4BB051A9338A3444Ad85c4A94bF25f6044
       Staking Token ($USB): 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
       Target Token ($stETH): 0x88D10dBf2A4dc90514D05A60595c26098c3393D2
       Staking Yield Token ($stETHx): 0xBc4647B83448b8Ed4b1730A0B3D10f1F67924d14
       Matching Yield Token ($stETH): 0x88D10dBf2A4dc90514D05A60595c26098c3393D2
    Pty Pool Above AARU: 0x7b98d35451fD7bE0eF642E64deb0Dcbafa72aD61
       Staking Token ($stETH): 0x88D10dBf2A4dc90514D05A60595c26098c3393D2
       Target Token ($USB): 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
       Staking Yield Token ($stETH): 0x88D10dBf2A4dc90514D05A60595c26098c3393D2
       Matching Yield Token ($stETHx): 0xBc4647B83448b8Ed4b1730A0B3D10f1F67924d14
  $WBTC Vault
    Vault Address: 0x43E549c1bfA8233135c846A3C667E728623D7F34
    Asset Token ($WBTC): 0x5C85863ADbb8318EfA1E7a3c694E1b33692e97E2
    Asset Price Feed: 0xCC7ed4196d45b7A03018c01692d576e69c222f8f
    $WBTCx Token: 0x31709e0ABc7901dE6406E956b5E30ca2f20081E7
       Vault: 0x43E549c1bfA8233135c846A3C667E728623D7F34
    Pty Pool Below AARS: 0x3823D00117b0c34311Bcda86c6A87d2Fb467B000
       Staking Token ($USB): 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
       Target Token ($WBTC): 0x5C85863ADbb8318EfA1E7a3c694E1b33692e97E2
       Staking Yield Token ($WBTCx): 0x31709e0ABc7901dE6406E956b5E30ca2f20081E7
       Matching Yield Token ($WBTC): 0x5C85863ADbb8318EfA1E7a3c694E1b33692e97E2
    Pty Pool Above AARU: 0x00D7Ce24EF641CE0CBebA842750dF633b080d2ec
       Staking Token ($WBTC): 0x5C85863ADbb8318EfA1E7a3c694E1b33692e97E2
       Target Token ($USB): 0xF6D06Eab400c62b34baec3e5d1B901b1064D34F9
       Staking Yield Token ($WBTC): 0x5C85863ADbb8318EfA1E7a3c694E1b33692e97E2
       Matching Yield Token ($WBTCx): 0x31709e0ABc7901dE6406E956b5E30ca2f20081E7
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.