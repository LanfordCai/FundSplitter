import FungibleToken from "../contracts/utility/FungibleToken.cdc"
import FUSD from "../contracts/utility/FUSD.cdc"

pub fun main(address: Address): UFix64 {
    let account = getAccount(address)

    let vaultRef = account
        .getCapability(/public/fusdBalance)
        .borrow<&FUSD.Vault{FungibleToken.Balance}>()
        ?? panic("Could not borrow Balance capability")

    return vaultRef.balance
}