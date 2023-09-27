import path from "path"
import {
  emulator,
  init,
  getFlowBalance,
} from "@onflow/flow-js-testing";
import { claimRewards, claimRewardsForAddress, claimRewardsWithFakeFloat, createFakeFloats, createFlowFUSDSplitter, createFlowFusdSplitter, createSplitterAccount, deployContracts, getAdmin, getAlice, getFloatSerials, getFusdBalance, getRemainBalances, getSplitterBalances, getTesters, getUnallocatedBalances, mintFusd, setupFusd, transferFloat, transferFlow, transferFusd } from "./helpers";

jest.setTimeout(100000)

describe("Splitter", () => {
  beforeEach(async () => {
    const basePath = path.resolve(__dirname, "..")
    const port = 8080
    await init(basePath, { port })
    await emulator.start()
    await new Promise(r => setTimeout(r, 2000));
    return await deployContracts()
  })

  afterEach(async () => {
    await emulator.stop();
    return await new Promise(r => setTimeout(r, 2000));
  })

  it("It should be okay if we create a splitter and claim rewards with valid parameters.", async () => {
    // create Splitter
    let admin = await getAdmin()
    await setupFusd(admin)
    await mintFusd(admin, 1000.0, admin)

    let [alice, bob, carl, david, eva, frank] = await getTesters()
    // 3000 == 30%
    const [createResult, createError] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "2000", [carl]: "1000", [david]: "1000", [eva]: "2050", [frank]: "950"
    })

    expect(createError).toBeNull()
    let splitter = getSplitter(createResult.events)
    let eventId = getEventId(createResult.events)

    // distribute FLOW and FUSD
    await checkFlowBalances({
      [alice]: "10.00100000", [bob]: "10.00100000", [carl]: "10.00100000", [david]: "10.00100000", [eva]: "10.00100000", [frank]: "10.00100000" 
    })
    await checkFusdBalances({
      [alice]: "0.00000000", [bob]: "0.00000000", [carl]: "0.00000000", [david]: "0.00000000", [eva]: "0.00000000", [frank]: "0.00000000" 
    })
    await checkSplitterBalances(splitter, eventId, alice, "0.00000000", "0.00000000")

    let [, transferError1] = await transferFlow(admin, splitter, "100.0")
    expect(transferError1).toBeNull()
    let [, transferError2] = await transferFusd(admin, splitter, "50.0")
    expect(transferError2).toBeNull()

    await checkSplitterBalances(splitter, eventId, alice, "30.00000000", "15.00000000")

    let [, claimError1] = await claimRewards(alice, splitter)
    expect(claimError1).toBeNull()

    await checkFlowBalances({
      [alice]: "40.00100000", [bob]: "10.00100000", [carl]: "10.00100000", [david]: "10.00100000", [eva]: "10.00100000", [frank]: "10.00100000" 
    })
    await checkFusdBalances({
      [alice]: "15.00000000", [bob]: "0.00000000", [carl]: "0.00000000", [david]: "0.00000000", [eva]: "0.00000000", [frank]: "0.00000000" 
    })
    await checkSplitterBalances(splitter, eventId, alice, "0.00000000", "0.00000000")
  })

  it("It should not be okay if we create a splitter with invalid parameters.", async () => {
    // create Splitter
    let admin = await getAdmin()
    await setupFusd(admin)
    await mintFusd(admin, 1000.0, admin)

    let [alice, bob, carl] = await getTesters()
    const [, createError1] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "2000", [carl]: "1000"
    })
    expect(createError1.includes("Invalid shares")).toBeTruthy()

    const [, createError2] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "10000", [carl]: "1000"
    })
    expect(createError2.includes("Invalid shares")).toBeTruthy()

    const [, createError3] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "7000", [carl]: "0"
    })
    expect(createError3.includes("Invalid shares")).toBeTruthy()

    const [, createError4] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "100000", [carl]: "1000.0"
    })
    expect(createError4.includes("decodeing argument failed")).toBeTruthy()

    const [, createError5] = await createFlowFusdSplitter(admin, {})
    expect(createError5.includes("Recipients should not be empty")).toBeTruthy()

    const [, createError6] = await createSplitterAccount(admin, [], [], [], "", "", "TEST", "", true, {
      [alice]: "3000", [bob]: "7000"
    }, "1.0")
    expect(createError6.includes("Invalid tokens")).toBeTruthy()

    const [, createError7] = await createSplitterAccount(admin, ["0x0ae53cb6e3f42a79", "0x0ae53cb6e3f42a79"], 
      ["FlowToken", "FlowToken"], ["flowTokenReceiver", "flowTokenReceiver"], "", "", "TEST", "", true, {
      [alice]: "3000", [bob]: "7000"
    }, "1.0")
    expect(createError7.includes("Invalid tokens")).toBeTruthy()

    const [, createError8] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "7000"
    }, "0.009")
    expect(createError8.includes("Init amount should be greater than 0.01")).toBeTruthy()
  })

  it("The remaining funds after distribution should be used for subsequent distributions.", async () => {
    // create Splitter
    let admin = await getAdmin()
    await setupFusd(admin)
    await mintFusd(admin, 1000.0, admin)

    let [alice, bob] = await getTesters()
    const [createResult, createError] = await createFlowFusdSplitter(admin, {
      [alice]: "9999", [bob]: "1"
    })

    expect(createError).toBeNull()
    let splitter = getSplitter(createResult.events)
    let eventId = getEventId(createResult.events)

    // distribute FLOW and FUSD
    await checkFlowBalances({[alice]: "10.00100000", [bob]: "10.00100000"})
    await checkSplitterBalances(splitter, eventId, alice, "0.00000000", "0.00000000")
    await checkSplitterBalances(splitter, eventId, bob, "0.00000000", "0.00000000")
    await checkUnallocatedBalances(splitter, "0.00000000", "0.00000000")

    let [, transferError1] = await transferFlow(admin, splitter, "0.00005000")
    expect(transferError1).toBeNull()

    // The part less than 0.0001 will be retained for the next distribution
    await checkSplitterBalances(splitter, eventId, alice, "0.00000000", "0.00000000")
    await checkSplitterBalances(splitter, eventId, bob, "0.00000000", "0.00000000")
    await checkUnallocatedBalances(splitter, "0.00005000", "0.00000000")

    let [, claimError1] = await claimRewards(alice, splitter)
    expect(claimError1).toBeNull()
    let [, claimError2] = await claimRewards(bob, splitter)
    expect(claimError2).toBeNull()
    await checkFlowBalances({[alice]: "10.00100000", [bob]: "10.00100000"})

    let [, transferError2] = await transferFlow(admin, splitter, "0.00019000")
    expect(transferError2).toBeNull()

    // Agin, the part less than 0.0001 will be retained for the next distribution.
    await checkSplitterBalances(splitter, eventId, alice, "0.00019998", "0.00000000")
    await checkSplitterBalances(splitter, eventId, bob, "0.00000002", "0.00000000")
    await checkUnallocatedBalances(splitter, "0.00004000", "0.00000000")

    let [, claimError3] = await claimRewards(alice, splitter)
    expect(claimError3).toBeNull()
    let [, claimError4] = await claimRewards(bob, splitter)
    expect(claimError4).toBeNull()
    await checkFlowBalances({[alice]: "10.00119998", [bob]: "10.00100002"})
  })

  it("A user can have multiple FLOAT shares.", async () => {
    // create Splitter
    let admin = await getAdmin()
    await setupFusd(admin)
    await mintFusd(admin, 1000.0, admin)

    let [alice, bob, carl] = await getTesters()
    // 3000 == 30%
    const [createResult, createError] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "3000", [carl]: "4000"
    })

    expect(createError).toBeNull()
    let splitter = getSplitter(createResult.events)
    let carlFloatId = getFloatId(createResult.events, carl)

    await transferFloat(carl, carlFloatId, alice)
    await checkFlowBalances({
      [alice]: "10.00100000", [bob]: "10.00100000", [carl]: "10.00100000"
    })

    let [, transferError1] = await transferFlow(admin, splitter, "100.0")
    expect(transferError1).toBeNull()

    let [, claimError1] = await claimRewards(alice, splitter)
    expect(claimError1).toBeNull()
    await checkFlowBalances({
      [alice]: "80.00100000", [bob]: "10.00100000", [carl]: "10.00100000"
    })

    let [, transferError2] = await transferFlow(admin, splitter, "100.0")
    expect(transferError2).toBeNull()

    let [, claimError2] = await claimRewards(bob, splitter)
    expect(claimError2).toBeNull()
    await checkFlowBalances({
      [alice]: "80.00100000", [bob]: "70.00100000", [carl]: "10.00100000"
    })

    let [, claimError3] = await claimRewards(alice, splitter)
    expect(claimError3).toBeNull()
    await checkFlowBalances({
      [alice]: "150.00100000", [bob]: "70.00100000", [carl]: "10.00100000"
    })
  })

  it("A user can't claim with invalid FLOAT.", async () => {
    // create Splitter
    let admin = await getAdmin()
    await setupFusd(admin)
    await mintFusd(admin, 1000.0, admin)

    let [alice, bob, carl] = await getTesters()
    // 3000 == 30%
    const [createResult, createError] = await createFlowFusdSplitter(admin, {
      [alice]: "3000", [bob]: "7000"
    })

    expect(createError).toBeNull()
    let splitter = getSplitter(createResult.events)

    let [, transferError1] = await transferFlow(admin, splitter, "100.0")
    expect(transferError1).toBeNull()

    let [, createFakeError] = await createFakeFloats(carl)
    expect(createFakeError).toBeNull()

    const [, claimError] = await claimRewardsWithFakeFloat(carl, splitter)
    expect(claimError.includes("Invalid event")).toBeTruthy()
  })

  it("A Splitter Account can be used as a shareholder of another Splitter Account.", async () => {
    // create Splitter
    let admin = await getAdmin()
    await setupFusd(admin)
    await mintFusd(admin, 1000.0, admin)

    let [alice, bob] = await getTesters()
    // 3000 == 30%
    const [createResult1, createError1] = await createFlowFusdSplitter(admin, {
      [alice]: "4000", [bob]: "6000"
    })

    expect(createError1).toBeNull()
    let splitter1 = getSplitter(createResult1.events)

    const [createResult2, createError2] = await createFlowFusdSplitter(admin, {
      [splitter1]: "5000", [bob]: "5000"
    })

    expect(createError2).toBeNull()
    let splitter2 = getSplitter(createResult2.events)

    // distribute FLOW and FUSD
    await checkFlowBalances({
      [alice]: "10.00100000", [bob]: "10.00100000", [splitter1]: "1.00100000"
    })

    let [, transferError1] = await transferFlow(admin, splitter1, "100.0")
    expect(transferError1).toBeNull()
    let [, transferError2] = await transferFlow(admin, splitter2, "200.0")
    expect(transferError2).toBeNull()

    let [, claimError1] = await claimRewardsForAddress(bob, splitter2, splitter1)
    expect(claimError1).toBeNull()
    let [, claimError2] = await claimRewards(alice, splitter1)
    expect(claimError2).toBeNull()
    let [, claimError3] = await claimRewards(bob, splitter1)
    expect(claimError3).toBeNull()
    let [, claimError4] = await claimRewards(bob, splitter2)
    expect(claimError4).toBeNull()

    await checkFlowBalances({
      [alice]: "90.00100000", [bob]: "230.00100000", [splitter1]: "1.00100000"
    })
  })
})

const getSplitter = (events) => {
  var splitter = null
  for (let i = 0; i < events.length; i++) {
    let e = events[i]
    if (e.type.includes("SplitterAccountCreated")) {
      splitter = e.data.splitter
      break
    }
  }
  return splitter
}

const getEventId = (events) => {
  var eventId = null
  for (let i = 0; i < events.length; i++) {
    let e = events[i]
    if (e.type.includes("FLOAT.FLOATEventCreated")) {
      eventId = e.data.eventId
      break
    }
  }
  return eventId
}

const getFloatId = (events, account) => {
  for (let i = 0; i < events.length; i++) {
    let e = events[i]
    if (e.type.includes("FLOAT.FLOATTransferred")) {
      if (account == e.data.newOwner) {
        return e.data.id
      }
    }
  }
  return null
}

const checkFlowBalances = async (expects) => {
  for (var [address, balance] of Object.entries(expects)) {
    let [get,,] = await getFlowBalance(address)
    expect(get).toBe(balance)
  }
}

const checkFusdBalances = async (expects) => {
  for (var [address, balance] of Object.entries(expects)) {
    let get = await getFusdBalance(address)
    expect(get).toBe(parseFloat(balance))
  }
}

const checkSplitterBalances = async (splitter, eventId, account, expectFlow, expectFusd) => {
  let splitterBalances = await getSplitterBalances(splitter)

  let serials = await getFloatSerials(account, eventId)
  expect(serials.length).toBe(1)
  let serial = serials[0]
  expect(splitterBalances["flowTokenReceiver"][serial]).toBe(expectFlow)
  expect(splitterBalances["fusdReceiver"][serial]).toBe(expectFusd) 
}

const checkUnallocatedBalances = async (splitter, expectFlow, expectFusd) => {
  let balances = await getUnallocatedBalances(splitter)

  expect(balances["flowTokenReceiver"]).toBe(expectFlow)
  expect(balances["fusdReceiver"]).toBe(expectFusd) 
}