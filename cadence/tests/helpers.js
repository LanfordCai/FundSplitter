import { 
  getAccountAddress,
  deployContractByName,
  mintFlow,
  sendTransaction,
  executeScript,
  shallResolve,
  shallPass
} from "@onflow/flow-js-testing"

export const getAdmin = async () => getAccountAddress("Admin")
export const getAlice = async () => getAccountAddress("Alice")
export const getBob = async () => getAccountAddress("Bob")
export const getCarl = async () => getAccountAddress("Carl")
export const getDavid = async () => getAccountAddress("David")
export const getEva = async () => getAccountAddress("Eva")
export const getFrank = async () => getAccountAddress("Frank")

export const deployContracts = async () => {
  const deployer = await getAdmin()
  await mintFlow(deployer, 1000.0)
  await deployByName(deployer, "utility/NonFungibleToken")
  await deployByName(deployer, "utility/MetadataViews")
  await deployByName(deployer, "utility/FUSD")
  await deployByName(deployer, "utility/FindViews")
  await deployByName(deployer, "utility/FLOAT")
  await deployByName(deployer, "FundSplitter")
}

export const deployByName = async (deployer, contractName, args) => {
  const [, error] = await deployContractByName({ to: deployer, name: contractName, args: args })
  expect(error).toBeNull()
}

export const transferFlow = async (signer, to, amount) => {
  const signers = [signer]
  const name = "transfer_token"
  const args = ["flowTokenVault", "flowTokenReceiver", to, amount]
  return await sendTransaction({ name: name, signers: signers, args: args})
}

export const getTesters = async () => {
  let testers = [await getAlice(), await getBob(), await getCarl(), await getDavid(), await getEva(), await getFrank()]
  for (let i = 0; i < testers.length; i++) {
    let tester = testers[i]
    await setupFloatCollection(tester)
    await mintFlow(tester, 10.0)
    await setupFusd(tester)
  }
  return testers
}

// FundSplitter

export const claimRewards = async (signer, splitterAddress) => {
  const signers = [signer]
  const name = "claim_rewards"
  const args = [splitterAddress, ["flowTokenReceiver", "fusdReceiver"]]
  return await sendTransaction({ name: name, signers: signers, args: args})
}

export const claimRewardsForAddress = async (signer, splitterAddress, address) => {
  const signers = [signer]
  const name = "claim_rewards_for_address"
  const args = [splitterAddress, address, ["flowTokenReceiver", "fusdReceiver"]]
  return await sendTransaction({ name: name, signers: signers, args: args})
}

export const claimRewardsWithFakeFloat = async (signer, splitterAddress) => {
  const signers = [signer]
  const name = "claim_rewards_with_fake_float"
  const args = [splitterAddress]
  return await sendTransaction({ name: name, signers: signers, args: args})
}

export const createSplitterAccount = async (
  signer,
  tokenContractAddresses, tokenContractNames, tokenReceiverPaths,
  description, logo, eventName, url, transferrable, recipients, initAmount
) => {
  const signers = [signer]
  const name = "create_splitter_account"
  const args = [
    tokenContractAddresses, tokenContractNames, tokenReceiverPaths,
    description, logo, eventName, url, transferrable, recipients, initAmount
  ]
  return await sendTransaction({ name: name, signers: signers, args: args})
}

export const createFlowFusdSplitter = async (signer, recipients, initAmount) => {
  let logo = "https://assets-global.website-files.com/5f734f4dbd95382f4fdfa0ea/6395e6749db8fe00a41cc279_flow-flow-logo.svg"
  let deployer = await getAdmin()
  return await createSplitterAccount(
    signer, ["0x0ae53cb6e3f42a79", deployer], ["FlowToken", "FUSD"], ["flowTokenReceiver", "fusdReceiver"],
    "Fund splitter for L33 Hackathon", logo, "Splitter", "https://lanford33.com", true,
    recipients, initAmount || "1.0"
  )
}

export const getSplitterBalances = async (splitter) => {
  const name = "get_splitter_balances"
  const args = [splitter, ["flowTokenReceiver", "fusdReceiver"]]
  const [result, error] = await executeScript({ name: name, args: args })
  expect(error).toBeNull()
  return result
}

export const getUnallocatedBalances = async (splitter) => {
  const name = "get_unallocated_balances"
  const args = [splitter, ["flowTokenReceiver", "fusdReceiver"]]
  const [result, error] = await executeScript({ name: name, args: args })
  expect(error).toBeNull()
  return result
}

// FLOAT

export const getFloatSerials = async (address, eventId) => {
  const name = "get_float_serials"
  const args = [address, eventId]
  const [result, error] = await executeScript({ name: name, args: args })
  expect(error).toBeNull()
  return result
}

export const setupFloatCollection = async (signer) => {
  const signers = [signer]
  const name = "setup_float_collection"
  const args = []
  return await sendTransaction({ name: name, signers: signers, args: args})
}

export const transferFloat = async (signer, floatId, recipient) => {
  const signers = [signer]
  const args = [floatId, recipient]
  const name = "transfer_float"
  await shallPass(sendTransaction({ name: name, args: args, signers: signers }))
}

export const createFakeFloats = async (signer) => {
  const signers = [signer]
  const args = []
  const name = "create_fake_floats"
  return await sendTransaction({ name: name, args: args, signers: signers })
}

// FUSD

export const setupFusd = async (signer) => {
  const signers = [signer]
  const name = "setup_fusd"
  await shallPass(sendTransaction({ name: name, signers: signers }))
}

export const mintFusd = async (minter, amount, recipient) => {
  const signers = [minter]
  const args = [amount, recipient]
  const name = "mint_fusd"
  await shallPass(sendTransaction({ name: name, args: args, signers: signers }))
}

export const getFusdBalance = async (account) => {
  const [result, ] = await shallResolve(executeScript({ name: "get_fusd_balance", args: [account] }))
  return parseFloat(result)
}

export const transferFusd = async (signer, to, amount) => {
  const signers = [signer]
  const name = "transfer_token"
  const args = ["fusdVault", "fusdReceiver", to, amount]
  return await sendTransaction({ name: name, signers: signers, args: args})
}