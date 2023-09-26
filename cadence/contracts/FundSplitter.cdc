import FungibleToken from "./utility/FungibleToken.cdc"
import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import FLOAT from "./utility/FLOAT.cdc"

pub contract FundSplitter {

    pub event ContractInitialized()
    pub event SplitterAccountCreated(splitter: Address, creator: Address)
    pub event SplitterDeposit(splitter: Address, amount: UFix64)
    pub event SplitterClaimed(splitter: Address, amount: UFix64, receiver: Address)

    pub resource interface ISplitterPublic {
        pub let tokenInfo: TokenInfo
        pub let eventId: UInt64
        pub var remainBalance: UFix64
        pub let balances: {UInt64: UFix64}
        pub fun claim(float: &FLOAT.NFT)
    }

    // can only be created by using this contract
    pub resource Splitter: FungibleToken.Receiver, ISplitterPublic {

        pub let vault: @FungibleToken.Vault
        pub let tokenInfo: TokenInfo
        pub let eventId: UInt64
        pub var remainBalance: UFix64
        // How about using @{UInt64: FungibleToken.Vault} here?
        // compare gas comsumption
        // serial => balance
        pub let balances: {UInt64: UFix64}

        pub fun deposit(from: @FungibleToken.Vault) {
            pre {
                from.balance > 0.0: "Deposit amount should be greater than 0"
            }

            let depositAmount = from.balance
            self.remainBalance = self.remainBalance + from.balance
            self.vault.deposit(from: <-from)

            let distributionAmount = self.remainBalance - (self.remainBalance % 0.0001)
            if distributionAmount == 0.0 {
                return
            }

            let serials = self.balances.keys
            let events = getAccount(self.owner!.address)
                .getCapability(FLOAT.FLOATEventsPublicPath)
                .borrow<&{FLOAT.FLOATEventsPublic}>()
                ?? panic("Borrow FLOATEvents failed")
            let event = events.borrowPublicEventRef(eventId: self.eventId)!

            for serial in serials {
                let extraData = event.getExtraFloatMetadata(serial: serial)
                let share = (extraData["share"]! as! UInt16?)!
                let amount = distributionAmount * (UFix64(share) / 10000.0)

                let b = self.balances[serial]!
                self.balances[serial] = b + amount
                self.remainBalance = self.remainBalance - amount
            }

            emit SplitterDeposit(splitter: self.owner!.address, amount: depositAmount)
        }

        pub fun claim(float: &FLOAT.NFT) {
            pre {
                float.eventId == self.eventId: "Invalid event"
                self.balances.containsKey(float.serial): "Ineligible FLOAT"
            }

            let balance = self.balances[float.serial]!
            self.balances[float.serial] = 0.0
            if balance == 0.0 {
                return
            }

            let claimee = float.owner!.address
            let receiver = getAccount(claimee)
                .getCapability(self.tokenInfo.receiverPublicPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow Receiver from claimee")

            let v <- self.vault.withdraw(amount: balance)
            receiver.deposit(from: <- v)

            emit SplitterClaimed(splitter: self.owner!.address, amount: balance, receiver: claimee)
        }

        destroy() {
            pre {
                self.vault.balance == 0.0: "vault is not empty, please withdraw all funds before delete DROP"
            }

            destroy self.vault
        }

        init(
            event: &FLOAT.FLOATEvent{FLOAT.FLOATEventPublic},
            tokenInfo: TokenInfo
        ) {
            self.eventId = event.eventId

            self.tokenInfo = tokenInfo

            let tokenAccount = getAccount(tokenInfo.contractAddress)
            let tokenContract = tokenAccount.contracts.borrow<&FungibleToken>(name: tokenInfo.contractName)
                ?? panic("borrow token contract failed! contractAddress: "
                    .concat(tokenInfo.contractAddress.toString())
                    .concat(" contractName: ")
                    .concat(tokenInfo.contractName)
                )

            self.vault <- tokenContract.createEmptyVault()
            self.remainBalance = 0.0

            let tokenIdentifiers = event.getClaims().values
            var balances: {UInt64: UFix64} = {}
            for tokenId in tokenIdentifiers {
                balances[tokenId.serial] = 0.0
            }
            self.balances = balances
        }
    }

    pub struct TokenInfo {
        pub let contractAddress: Address
        pub let contractName: String
        pub let receiverPublicPath: PublicPath

        init(contractAddress: Address, contractName: String, receiverPublicPath: PublicPath) {
            self.contractAddress = contractAddress
            self.contractName = contractName
            self.receiverPublicPath = receiverPublicPath
        }
    }

    // FIXME: we use AuthAccount here
    pub fun createSplitterAccount(
        signer: AuthAccount,
        tokens: [TokenInfo],
        description: String,
        logo: String,
        name: String,
        url: String,
        transferrable: Bool,
        recipients: {Address: UInt16},
        initAmount: UFix64
    ): Address {
        pre {
            tokens.length > 0: "Tokens should not be empty"
            recipients.keys.length > 0: "Recipients should not be empty"
            self.withValidShares(recipients): "Invalid shares"
            initAmount > 0.01: "Init amount should be greater than 0.01"
        }

        let initVault <- signer
            .borrow<&{FungibleToken.Provider}>(from: /storage/flowTokenVault)!
            .withdraw(amount: initAmount)

        let acct = AuthAccount(payer: signer)
        acct.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            .borrow()!
            .deposit(from: <- initVault)

        self.setupFLOAT(acct)

        let events = acct.borrow<&FLOAT.FLOATEvents>(from: FLOAT.FLOATEventsStoragePath) 
            ?? panic("Could not borrow the FLOATEvents from the account.")
        let eventId = events.createEvent(
            claimable: false,
            description: description,
            image: logo,
            name: name,
            transferrable: transferrable,
            url: url,
            verifiers: [],
            allowMultipleClaim: false,
            certificateType: "certificate",
            extraMetadata: {}
        )

        let event = events.borrowEventRef(eventId: eventId)!
        self.distributeFLOATs(event: event, recipients: recipients)
        let eventPublicRef = events.borrowPublicEventRef(eventId: eventId)!

        for i, tokenInfo in tokens {
            self.createSplitter(acct: acct, eventPublicRef: eventPublicRef, tokenInfo: tokenInfo)    
        }

        emit SplitterAccountCreated(splitter: acct.address, creator: signer.address)
        return acct.address
    }

    access(self) fun withValidShares(_ recipients: {Address: UInt16}): Bool {
        var sum: UInt16 = 0
        for v in recipients.values {
            assert(v > 0, message: "Share should not be 0")
            sum = sum + v
        }
        return sum == 10000
    }

    access(self) fun createSplitter(acct: AuthAccount, eventPublicRef: &FLOAT.FLOATEvent{FLOAT.FLOATEventPublic}, tokenInfo: TokenInfo) {
        let splitter <- create Splitter(event: eventPublicRef, tokenInfo: tokenInfo)

        let identifier = "FundSplitter_".concat(tokenInfo.contractAddress.toString())
        let storagePath = StoragePath(identifier: identifier)!
        acct.save(<- splitter, to: storagePath)
        acct.unlink(tokenInfo.receiverPublicPath)
        acct.link<&{FungibleToken.Receiver, ISplitterPublic}>(tokenInfo.receiverPublicPath, target: storagePath)
    }

    access(self) fun setupFLOAT(_ acct: AuthAccount) {
        // SETUP FLOATEVENTS
        if acct.borrow<&FLOAT.FLOATEvents>(from: FLOAT.FLOATEventsStoragePath) == nil {
            acct.save(<- FLOAT.createEmptyFLOATEventCollection(), to: FLOAT.FLOATEventsStoragePath)
            acct.link<&FLOAT.FLOATEvents{FLOAT.FLOATEventsPublic, MetadataViews.ResolverCollection}>
                                (FLOAT.FLOATEventsPublicPath, target: FLOAT.FLOATEventsStoragePath)
        }
    }

    access(self) fun distributeFLOATs(event: &FLOAT.FLOATEvent, recipients: {Address: UInt16}): [UInt64] {
        var serials: [UInt64] = []
        for address in recipients.keys {
            let share = recipients[address]
			let recipientCollection = getAccount(address).getCapability(FLOAT.FLOATCollectionPublicPath)
                .borrow<&FLOAT.Collection{NonFungibleToken.CollectionPublic, FLOAT.CollectionPublic}>()
                ?? panic("Could not get the public FLOAT Collection from the recipient.")

			let tokenId = event.mint(recipient: recipientCollection, optExtraFloatMetadata: {"share": share})
            let float = recipientCollection.borrowFLOAT(id: tokenId)!
            serials.append(float.serial)
		}
        return serials
    }

    init() {
        emit ContractInitialized()
    }
}