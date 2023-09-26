import FLOAT from "../contracts/utility/FLOAT.cdc"
import NonFungibleToken from "../contracts/utility/NonFungibleToken.cdc"
import MetadataViews from "../contracts/utility/MetadataViews.cdc"

transaction {
    let floatEvents: &FLOAT.FLOATEvents
    let recipientCollection: &FLOAT.Collection
    prepare(acct: AuthAccount) {
        // SETUP COLLECTION
        if acct.borrow<&FLOAT.Collection>(from: FLOAT.FLOATCollectionStoragePath) == nil {
            acct.save(<- FLOAT.createEmptyCollection(), to: FLOAT.FLOATCollectionStoragePath)
            acct.link<&FLOAT.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection, FLOAT.CollectionPublic}>
                    (FLOAT.FLOATCollectionPublicPath, target: FLOAT.FLOATCollectionStoragePath)
        }

        // SETUP FLOATEVENTS
        if acct.borrow<&FLOAT.FLOATEvents>(from: FLOAT.FLOATEventsStoragePath) == nil {
            acct.save(<- FLOAT.createEmptyFLOATEventCollection(), to: FLOAT.FLOATEventsStoragePath)
            acct.link<&FLOAT.FLOATEvents{FLOAT.FLOATEventsPublic, MetadataViews.ResolverCollection}>
                    (FLOAT.FLOATEventsPublicPath, target: FLOAT.FLOATEventsStoragePath)
        }

        self.floatEvents = acct.borrow<&FLOAT.FLOATEvents>(from: FLOAT.FLOATEventsStoragePath)
            ?? panic("Could not borrow the FLOATEvents from the signer.")
        self.recipientCollection = acct.borrow<&FLOAT.Collection>(from: FLOAT.FLOATCollectionStoragePath)
            ?? panic("Could not borrow the FLOATCollection from the signer.")
    }

    execute {
        let eventId = self.floatEvents.createEvent(
            claimable: false, 
            description: "", 
            image: "", 
            name: "FAKE", 
            transferrable: false, 
            url: "",
            verifiers: [], 
            allowMultipleClaim: true,
            certificateType: "certificate",
            extraMetadata: {}
        )

        let e = self.floatEvents.borrowEventRef(eventId: eventId)!
        var counter = 0
        while counter < 2 {
            e.mint(recipient: self.recipientCollection, optExtraFloatMetadata: {"share": 2000})
            counter = counter + 1
        }
    }
}
