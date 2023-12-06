

```mermaid
classDiagram
note for WandProtocol "This is Entry point of Wand protocol"
class WandProtocol {
  +ProtocolSettings settings
  +$USB usb
  +Vault[] vaults
  +addVault(vault)
}
class ProtocolSettings {
  +address treasury
  +Params[] params
  +setTreasury(treasury)
  +updateConfig(default, min, max)
}
class Usb {
  +map userShares
  +uint256 totalShares
  +sharesOf(user)
  +transferShares(to, amount)
  +rebase(amount)
  +...()
}
class VaultCalculator {
  +AAR(vault)
  +getVaultState(vault)
  +calcMintPairsAtStabilityPhase(vault, assetAmount)
  +..()
}
namespace AssetVault {
  class Vault {
    +address asset
    +address priceFeed
    +address leveragedToken
    +address ptyPoolBelowAARS
    +address ptyPoolAboveAARU
    +mint(amount)
    +redeem(amount)
    +usbToLeveragedTokens(amount)
  }
  class IPriceFeed {
    +latestPrice()
  }
  class LeveragedToken {
    +mint(amount)
    +burn(amount)
    +...()
  }
  class PtyPool {
    +stake(amount)
    +claim(amount)
    +exit()
    +addRewards(amount)
    +...()
  }
}

<<interface>> IPriceFeed

WandProtocol --> ProtocolSettings
WandProtocol --> Usb
WandProtocol "1" --> "*" Vault
Vault --> VaultCalculator
Vault --> IPriceFeed
Vault --> LeveragedToken
Vault "1" --> "2" PtyPool


``````