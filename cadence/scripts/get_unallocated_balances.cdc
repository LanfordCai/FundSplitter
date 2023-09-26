import FundSplitter from "../contracts/FundSplitter"

pub fun main(splitterAddress: Address, receiverPaths: [String]): {String: UFix64} {
    let balances: {String: UFix64} = {}
    for receiverPath in receiverPaths {
        let path = PublicPath(identifier: receiverPath)!
        let splitter = getAccount(splitterAddress)
            .getCapability(path)
            .borrow<&{FundSplitter.ISplitterPublic}>()
            ?? panic("Could not borrow Splitter")
        balances[receiverPath] = splitter.getUnallocatedBalance()
    }
    return balances
}