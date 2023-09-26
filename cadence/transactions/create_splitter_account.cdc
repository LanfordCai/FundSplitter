import FundSplitter from "../contracts/FundSplitter"

transaction(
    tokenContractAddresses: [Address],
    tokenContractNames: [String],
    tokenReceiverPaths: [String],
    description: String,
    logo: String,
    name: String,
    url: String,
    transferrable: Bool,
    recipients: {Address: UInt16},
    initAmount: UFix64
) {
    let signer: AuthAccount
    prepare(signer: AuthAccount) {
        self.signer = signer
    }

    pre {
        tokenContractAddresses.length == tokenContractNames.length && tokenContractNames.length == tokenReceiverPaths.length: "invalid tokens info"
    }

    execute {
        let tokens: [FundSplitter.TokenInfo] = []
        for i, contractAddress in tokenContractAddresses {
            let contractName = tokenContractNames[i]!
            let receiverPath = PublicPath(identifier: tokenReceiverPaths[i]!)!
            let token = FundSplitter.TokenInfo(
                contractAddress: contractAddress,
                contractName: contractName,
                receiverPublicPath: receiverPath
            )
            tokens.append(token)
        }

        FundSplitter.createSplitterAccount(
            signer: self.signer,
            tokens: tokens,
            description: description,
            logo: logo,
            name: name,
            url: url,
            transferrable: transferrable,
            recipients: recipients,
            initAmount: initAmount
        )
    }
}