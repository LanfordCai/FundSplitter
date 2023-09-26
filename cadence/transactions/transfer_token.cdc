import FungibleToken from "../contracts/utility/FungibleToken.cdc"

transaction(
    providerPathStr: String,
    receiverPathStr: String,
    to: Address,
    amount: UFix64
) {
    let provider: &{FungibleToken.Provider}
    prepare(signer: AuthAccount) {
        let providerPath = StoragePath(identifier: providerPathStr)!
        self.provider = signer
            .borrow<&{FungibleToken.Provider}>(from: providerPath)
            ?? panic("Could not borrow Provider")
    }

    execute {
        let receiverPath = PublicPath(identifier: receiverPathStr)!
        let receiver = getAccount(to)
            .getCapability<&{FungibleToken.Receiver}>(receiverPath)
            .borrow()
            ?? panic("Could not borrow Receiver")

        let vault <- self.provider.withdraw(amount: amount)
        receiver.deposit(from: <- vault)
    }
}