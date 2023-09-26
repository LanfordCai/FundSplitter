import FundSplitter from "FundSplitter"
import FLOAT from "FLOAT"

transaction(splitterAddress: Address, receiverPaths: [String]) {

    let splitters: [&{FundSplitter.ISplitterPublic}]
    let collection: &FLOAT.Collection
    prepare(signer: AuthAccount) {
        self.splitters = []
        for receiverPath in receiverPaths {
            let path = PublicPath(identifier: receiverPath)!
            let splitter = getAccount(splitterAddress)
                .getCapability(path)
                .borrow<&{FundSplitter.ISplitterPublic}>()
                ?? panic("Could not borrow Splitter")
            self.splitters.append(splitter)
        }

        self.collection = signer.borrow<&FLOAT.Collection>(from: FLOAT.FLOATCollectionStoragePath)
            ?? panic("Could not borrow FLOAT collection")
    }

    execute {
        for s in self.splitters {
            let floatIds = self.collection.ownedIdsFromEvent(eventId: s.eventId)
            for floatId in floatIds {
                if let float = self.collection.borrowFLOAT(id: floatId) {
                    s.claim(float: float)
                }
            }
        }
    }
}