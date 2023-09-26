// MADE BY: Lanford33

// FundSplitter is used to distribute funds among a group of users according to a set ratio. 
// Unlike common bulk transfers, it has the following features:

// 1. FundSplitter provides a unified collection account (hereinafter referred to as the Splitter Account) 
//    for the team. The fund issuer does not need to use a bulk transfer tool, but can directly transfer 
//    the funds into the Splitter Account, and the distribution will be carried out by it.
// 2. The Splitter account is a keyless account, and FundSplitter will also revoke the keys of the deployer 
//    after stabilization, making the Splitter Account fully decentralized.
// 3. FundSplitter will distribute a FLOAT to each group member. This FLOAT serves as a Share certificate 
//    recording their distribution ratio. When creating the Splitter account, it can be set whether these FLOATs are transferrable. 
//    If these FLOATs are transferrable, then team members can freely transfer their distribution rights.

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
        // Splitter vault, used to store the unallocated funds
        pub let vault: @FungibleToken.Vault
        // The key is FLOAT serial and the value is unclaimed funds of that FLOAT
        pub let balances: @{UInt64: FungibleToken.Vault}

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

            let v = (&self.balances[float.serial] as &FungibleToken.Vault?)!
            // If there is nothing to claim, return fast
            let balance = v.balance
            if balance == 0.0 {
                return
            }

            // Transfer the claimed amount to the owner of the FLOAT
            let claimee = float.owner!.address
            let receiver = getAccount(claimee)
                .getCapability(self.tokenInfo.receiverPublicPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow Receiver from claimee")

            receiver.deposit(from: <- v.withdraw(amount: balance))
            emit SplitterClaimed(splitter: self.owner!.address, amount: balance, receiver: claimee)
        }

        // Get the unallocated balance in the splitter
        pub fun getUnallocatedBalance(): UFix64 {
            return self.vault.balance
        }

        // Get the balances allocated to FLOATs
        pub fun getFloatBalances(): {UInt64: UFix64} {
            let serials = self.balances.keys
            let balances: {UInt64: UFix64} = {}
            for serial in serials {
                let v = (&self.balances[serial] as &FungibleToken.Vault?)!
                balances[serial] = v.balance
            }
            return balances
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
            if self.vault.balance < 0.0001 {
                return
            }
            // Here we take an amount that is a multiple of 0.0001 from unallocated balance.
            let allocationAmount = self.vault.balance - (self.vault.balance % 0.0001)

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

                let v = (&self.balances[serial] as &FungibleToken.Vault?)!
                v.deposit(from: <- self.vault.withdraw(amount: amount))
            }

            emit SplitterDeposit(splitter: self.owner!.address, amount: depositAmount)
        }

        destroy() {
            pre {
                self.vault.balance == 0.0: "vault is not empty, please withdraw all funds before delete Splitter"
            }
            destroy self.vault

            let floatBalances = self.getFloatBalances()
            for v in floatBalances.values {
                assert(v == 0.0, message: "vault is not empty, please withdraw all funds before delete Splitter")
            }
            destroy self.balances
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
            var balances: @{UInt64: FungibleToken.Vault} <- {}
            for tokenId in tokenIdentifiers {
                balances[tokenId.serial] <-! tokenContract.createEmptyVault()
            }
            self.balances <- balances
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

    // Helper function to setup FLOAT
    // It creates and links a FLOATEvents collection to the account if it doesn't exist
    access(self) fun setupFLOAT(_ acct: AuthAccount) {
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