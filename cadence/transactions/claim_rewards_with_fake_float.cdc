import FundSplitter from "../contracts/FundSplitter"
import FLOAT from "../contracts/utility/FLOAT.cdc"

transaction(splitterAddress: Address) {
    let splitter: &{FundSplitter.ISplitterPublic}
    let collection: &FLOAT.Collection
    prepare(signer: AuthAccount) {
        self.splitter = getAccount(splitterAddress)
            .getCapability(/public/flowTokenReceiver)
            .borrow<&{FundSplitter.ISplitterPublic}>()
            ?? panic("Could not borrow Splitter")

        self.collection = signer.borrow<&FLOAT.Collection>(from: FLOAT.FLOATCollectionStoragePath)
            ?? panic("Could not borrow FLOAT collection")
    }

    execute {
        let floatIds = self.collection.getIDs()
        for floatId in floatIds {
            if let float = self.collection.borrowFLOAT(id: floatId) {
                if float.serial == 0 {
                    self.splitter.claim(float: float)
                }
            }
        }
    }
}