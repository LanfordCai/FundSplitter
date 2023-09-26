import FLOAT from "FLOAT"

pub fun main(address: Address, eventId: UInt64): [UInt64] {
    let collection = getAuthAccount(address)
        .borrow<&FLOAT.Collection>(from: FLOAT.FLOATCollectionStoragePath)
        ?? panic("Could not borrow FLOATCollection")

    let serials: [UInt64] = []
    let floatIds = collection.ownedIdsFromEvent(eventId: eventId)
    for floatId in floatIds {
        if let float = collection.borrowFLOAT(id: floatId) {
            serials.append(float.serial)
        }
    }
    return serials
}