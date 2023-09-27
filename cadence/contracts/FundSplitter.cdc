// MADE BY: Lanford33

// FundSplitter is a tool designed to distribute funds among a group of users, such as DAO members, based 
// on a predetermined ratio. Unlike standard bulk transfers, FundSplitter offers several unique features:
//
// 1. FundSplitter establishes a unified collection account (referred to hereafter as the Splitter Account)
//    for the team. This eliminates the need for the fund issuer to use a bulk transfer tool; they can 
//    instead directly transfer funds into the Splitter Account, and FundSplitter handles the distribution.
//
// 2. The Splitter Account is keyless. After the system stabilizes, FundSplitter revokes the deployer's keys, 
//    rendering the Splitter Account completely decentralized.
//
// 3. FundSplitter issues a FLOAT to each group member. This FLOAT acts as a share certificate, documenting 
//    their distribution ratio. During the creation of the Splitter Account, it can be determined whether 
//    these FLOATs are transferable. If they are, group members can freely sell or transfer their distribution 
//    rights.
//
// 4. One Splitter Account can serve as a shareholder of another Splitter Account, offering flexibility in 
//    managing distribution rights.

import FungibleToken from "FungibleToken"
import NonFungibleToken from "NonFungibleToken"
import MetadataViews from "MetadataViews"
import FLOAT from "FLOAT"

pub contract FundSplitter {

    /************************************************/
    /******************** EVENTS ********************/
    /************************************************/

    pub event ContractInitialized()
    pub event SplitterAccountCreated(splitter: Address, creator: Address)
    pub event SplitterDeposit(splitter: Address, amount: UFix64)
    pub event SplitterClaimed(splitter: Address, amount: UFix64, receiver: Address)

    /***********************************************/
    /**************** FUNCTIONALITY ****************/
    /***********************************************/

    // Public interface for the Splitter resource
    pub resource interface ISplitterPublic {
        // Token information of the splitter
        pub let tokenInfo: TokenInfo
        // FLOATEvent id associated with the splitter
        pub let eventId: UInt64
        // Used for claiming funds for the splitter
        pub fun claim(float: &FLOAT.NFT)
        // Used for getting the unallocated balance in the splitter
        pub fun getUnallocatedBalance(): UFix64
        // Used for getting the balances allocated to FLOATs.
        pub fun getFloatBalances(): {UInt64: UFix64}
    }

    // Splitter resource that implements FungibleToken.Receiver and ISplitterPublic
    // A Splitter will be linked to the token receiver path(e.g. /public/flowTokenReceiver)
    // so that the Splitter can handle deposits to the account
    // Splitter can only be created in this contract
    pub resource Splitter: FungibleToken.Receiver, ISplitterPublic {
        // Splitter vault, used to store the unclaimed funds
        pub let vault: @FungibleToken.Vault
        // The key is FLOAT serial and the value is allocated funds of that FLOAT
        pub let balances: {UInt64: UFix64}

        // implements ISplitterPublic
        pub let tokenInfo: TokenInfo
        pub let eventId: UInt64

        // A user should claim the funds with the FLOAT, and the funds will be sent to
        // the owner of the FLOAT.
        pub fun claim(float: &FLOAT.NFT) {
            pre {
                float.eventId == self.eventId: "Invalid event"
                self.balances.containsKey(float.serial): "Ineligible FLOAT"
            }

            // If there is nothing to claim, return fast
            let balance = self.balances[float.serial]!
            if balance == 0.0 {
                return
            }
            self.balances[float.serial] = 0.0

            // Transfer the claimed amount to the owner of the FLOAT
            let claimee = float.owner!.address
            let receiver = getAccount(claimee)
                .getCapability(self.tokenInfo.receiverPublicPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow Receiver from claimee")

            receiver.deposit(from: <- self.vault.withdraw(amount: balance))
            emit SplitterClaimed(splitter: self.owner!.address, amount: balance, receiver: claimee)
        }

        // Get the unallocated balance in the splitter
        pub fun getUnallocatedBalance(): UFix64 {
            var allocated: UFix64 = 0.0
            for b in self.balances.values {
                allocated = allocated + b
            }
            return self.vault.balance - allocated
        }

        // Get the balances allocated to FLOATs
        pub fun getFloatBalances(): {UInt64: UFix64} {
            return self.balances
        }

        // implements FungibleToken.Receiver 
        pub fun deposit(from: @FungibleToken.Vault) {
            pre {
                from.balance > 0.0: "Deposit amount should be greater than 0"
            }
            
            let depositAmount = from.balance
            self.vault.deposit(from: <-from)

            // Our minimum share is 0.01%. Currently, the minimum amount of tokens on Flow is 0.00000001. 
            // Therefore, only when the allocation amount is 0.00000001 * 10000 = 0.0001 (or its multiples), 
            // can the user holding one ten thousandth of the share also receive their share without 
            // suffering losses due to precision issues.
            //
            // If unallocated balance is less than 0.0001, return directly
            let unallocated = self.getUnallocatedBalance()
            if unallocated < 0.0001 {
                return
            }
            // Here we take an amount that is a multiple of 0.0001 from unallocated balance.
            let allocationAmount = unallocated - (unallocated % 0.0001)

            // Allocate the balance to each FLOAT
            let serials = self.balances.keys
            let events = getAccount(self.owner!.address)
                .getCapability(FLOAT.FLOATEventsPublicPath)
                .borrow<&{FLOAT.FLOATEventsPublic}>()
                ?? panic("Borrow FLOATEvents failed")
            let event = events.borrowPublicEventRef(eventId: self.eventId)!

            for serial in serials {
                // Take the corresponding share from the event and calculate the amount to be allocated
                let extraData = event.getExtraFloatMetadata(serial: serial)
                let share = (extraData["share"]! as! UInt16?)!
                let amount = allocationAmount * (UFix64(share) / 10000.0)

                let b = self.balances[serial]!
                self.balances[serial] = b + amount
            }

            emit SplitterDeposit(splitter: self.owner!.address, amount: depositAmount)
        }

        destroy() {
            pre {
                self.vault.balance == 0.0: "vault is not empty, please withdraw all funds before delete Splitter"
            }
            destroy self.vault
        }

        init(
            event: &FLOAT.FLOATEvent{FLOAT.FLOATEventPublic},
            tokenInfo: TokenInfo
        ) {
            self.eventId = event.eventId

            // Borrow token contract through token information for vault initialization
            self.tokenInfo = tokenInfo
            let tokenAccount = getAccount(tokenInfo.contractAddress)
            let tokenContract = tokenAccount.contracts.borrow<&FungibleToken>(name: tokenInfo.contractName)
                ?? panic("borrow token contract failed! contractAddress: "
                    .concat(tokenInfo.contractAddress.toString())
                    .concat(" contractName: ")
                    .concat(tokenInfo.contractName)
                )
            self.vault <- tokenContract.createEmptyVault()

            let tokenIdentifiers = event.getClaims().values
            var balances: {UInt64: UFix64} = {}
            for tokenId in tokenIdentifiers {
                balances[tokenId.serial] = 0.0
            }
            self.balances = balances
        }
    }

    // A helpful wrapper to hold token information
    pub struct TokenInfo {
        pub let contractAddress: Address
        pub let contractName: String
        // Public path for the token receiver capability
        pub let receiverPublicPath: PublicPath

        init(contractAddress: Address, contractName: String, receiverPublicPath: PublicPath) {
            self.contractAddress = contractAddress
            self.contractName = contractName
            self.receiverPublicPath = receiverPublicPath
        }

        pub fun getIdentifier(): String {
            return self.contractAddress.toString()
                .concat("_")
                .concat(self.contractName)
        }
    }

    // We pass the signer in here as a parameter to generate the Splitter Account. An alternative approach would be to 
    // generate the AuthAccount externally and then pass it in. However, the problem is, even if we can confirm that the
    // passed-in AuthAccount does not have any keys, we cannot guarantee that it has not been manipulated in ways beyond 
    // our expectations externally. The safest way is to ensure the Splitter Account is generated within the contract. 
    // After the deployer key of this contract is revoked, the concern about passing in the signer will be greatly alleviated.
    // 
    // NOTE: AuthAccount as an argument is a Cadence anti-pattern
    // SEE: https://developers.flow.com/cadence/anti-patterns#avoid-using-authaccount-as-a-function-parameter
    // But it is necessary here
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
            recipients.keys.length > 0: "Recipients should not be empty"
            initAmount > 0.01: "Init amount should be greater than 0.01"
            self.withValidTokens(tokens): "Invalid tokens"
            self.withValidShares(recipients): "Invalid shares"
        }

        // Add some FLOW to the Splitter Account to ensure it has sufficient storage fee.
        let initVault <- signer
            .borrow<&{FungibleToken.Provider}>(from: /storage/flowTokenVault)!
            .withdraw(amount: initAmount)

        let acct = AuthAccount(payer: signer)
        acct.getCapability<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            .borrow()!
            .deposit(from: <- initVault)

        // Setup the FLOAT for the new Splitter Account
        self.setupFLOAT(acct)

        // Create a new FLOAT event.
        // This event is used to mint FLOATs for the shareholders.
        // The host of this event is the keyless Splitter Account.
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

        // Mint FLOATs for the shareholders
        let event = events.borrowEventRef(eventId: eventId)!
        self.distributeFLOATs(event: event, recipients: recipients)

        // Create Splitters for the tokens
        let eventPublicRef = events.borrowPublicEventRef(eventId: eventId)!
        for i, tokenInfo in tokens {
            self.createSplitter(acct: acct, eventPublicRef: eventPublicRef, tokenInfo: tokenInfo)    
        }

        emit SplitterAccountCreated(splitter: acct.address, creator: signer.address)
        return acct.address
    }

    // Helper function to validate tokens
    // It checks whether the tokens array is empty or contains duplicate items
    access(self) fun withValidTokens(_ tokens: [TokenInfo]): Bool {
        if tokens.length == 0 {
            return false
        }

        let set: {String: Bool} = {}
        for token in tokens {
            set[token.getIdentifier()] = true
        }
        return set.keys.length == tokens.length
    }

    // Helper function to validate shares
    // It checks whether the sum of all shares is exactly 10000 (100%)
    access(self) fun withValidShares(_ recipients: {Address: UInt16}): Bool {
        var sum: UInt16 = 0
        for v in recipients.values {
            assert(v > 0, message: "Share should not be 0")
            sum = sum + v
        }
        return sum == 10000
    }

    // Helper function to create a Splitter
    // It creates a new Splitter resource, saves it to the account's storage
    // and links it to the token's receiver public path
    access(self) fun createSplitter(acct: AuthAccount, eventPublicRef: &FLOAT.FLOATEvent{FLOAT.FLOATEventPublic}, tokenInfo: TokenInfo) {
        let splitter <- create Splitter(event: eventPublicRef, tokenInfo: tokenInfo)

        let identifier = "FundSplitter_".concat(tokenInfo.getIdentifier())

        let storagePath = StoragePath(identifier: identifier)!
        acct.save(<- splitter, to: storagePath)
        acct.unlink(tokenInfo.receiverPublicPath)
        acct.link<&{FungibleToken.Receiver, ISplitterPublic}>(tokenInfo.receiverPublicPath, target: storagePath)
    }

    // Helper function to set up FLOAT
    // This function creates and links a FLOAT collection and a FLOATEvents collection to the account if they don't already exist
    access(self) fun setupFLOAT(_ acct: AuthAccount) {
        // A FLOAT collection is created and linked for the Splitter Account so that it can be used
        // as a shareholder of another Splitter Account
        if acct.borrow<&FLOAT.Collection>(from: FLOAT.FLOATCollectionStoragePath) == nil {
            acct.save(<- FLOAT.createEmptyCollection(), to: FLOAT.FLOATCollectionStoragePath)
            acct.link<&FLOAT.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection, FLOAT.CollectionPublic}>
                (FLOAT.FLOATCollectionPublicPath, target: FLOAT.FLOATCollectionStoragePath)
        }

        // If a FLOATEvents collection does not exist, it is created and linked to the account
        if acct.borrow<&FLOAT.FLOATEvents>(from: FLOAT.FLOATEventsStoragePath) == nil {
            acct.save(<- FLOAT.createEmptyFLOATEventCollection(), to: FLOAT.FLOATEventsStoragePath)
            acct.link<&FLOAT.FLOATEvents{FLOAT.FLOATEventsPublic, MetadataViews.ResolverCollection}>
                                (FLOAT.FLOATEventsPublicPath, target: FLOAT.FLOATEventsStoragePath)
        }
    }

    // Helper function to distribute FLOATs
    // It mints new FLOATs and distributes them to the recipients based on their shares
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