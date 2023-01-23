const { ethers, waffle } = require("hardhat");

const { tokensBN } = require("../../helpers/utils");

const { epnsContractFixture, tokenFixture } = require("../common/fixturesV2");
const { expect } = require("../common/expect");
const createFixtureLoader = waffle.createFixtureLoader;

const weiToEth = (eth) => ethers.utils.formatEther(eth);

describe("EPNS CoreV2 Protocol", function () {
  const ADD_CHANNEL_MIN_POOL_CONTRIBUTION = tokensBN(50);
  const ADD_CHANNEL_MAX_POOL_CONTRIBUTION = tokensBN(250000 * 50);
  const ADJUST_FOR_FLOAT = 10 ** 7;

  let PushToken;
  let EPNSCoreV1Proxy;
  let EPNSCommV1Proxy;
  let ADMIN;
  let ALICE;
  let BOB;
  let CHARLIE;
  let CHANNEL_CREATOR;
  let ADMINSIGNER;
  let ALICESIGNER;
  let BOBSIGNER;
  let CHARLIESIGNER;
  let CHANNEL_CREATORSIGNER;

  let loadFixture;
  before(async () => {
    [wallet, other] = await ethers.getSigners();
    loadFixture = createFixtureLoader([wallet, other]);
  });

  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    const [
      adminSigner,
      aliceSigner,
      bobSigner,
      charlieSigner,
      channelCreatorSigner,
    ] = await ethers.getSigners();

    ADMINSIGNER = adminSigner;
    ALICESIGNER = aliceSigner;
    BOBSIGNER = bobSigner;
    CHARLIESIGNER = charlieSigner;
    CHANNEL_CREATORSIGNER = channelCreatorSigner;

    ADMIN = await adminSigner.getAddress();
    ALICE = await aliceSigner.getAddress();
    BOB = await bobSigner.getAddress();
    CHARLIE = await charlieSigner.getAddress();
    CHANNEL_CREATOR = await channelCreatorSigner.getAddress();

    ({ PROXYADMIN, EPNSCoreV1Proxy, EPNSCommV1Proxy, ROUTER, PushToken } =
      await loadFixture(epnsContractFixture));

  });
  /***
   * CHECKPOINTS TO CONSIDER WHILE TESTING -> Overall Stake-N-Claim Tests
   * ------------------------------------------
   * 1. Stake
   *  - Staking function should execute as expected-Updates user's staked amount, PUSH transfer etc ✅
   *  - FIRST stake should update user's stakedWeight, stakedAmount and other imperative details accurately
   *  - Consecutive stakes should update details accurately: 2 cases
   *    - a. User staking again in same epoch, Should add user's stake details in the same epoch
   *    - b. User staking in different epoch, should update the epoch's in between with last epoch details - and last epoch with latest details
   * 
   * 
   * 2. UnStake
   *  - UnStake function should execute as expected ✅
   *  - UnStake functions shouldn't be executed when Caller is Not a Staker.✅
   *  - UnStaking right after staking should lead to any rewards.
   *  - UnStaking should also transfer claimable rewards for the Caller ✅
   * 
   * 2. Reward Calculation and Claiming Reward Tests
   *  - First Claim of stakers should execute as expected ✅
   *  - First Claim: Stakers who hold longer should get more rewards ✅
   *  - Verify that total reward actually gets distrubuted between stakers in one given epoch ✅
   *  - Rewards should adjust automatically if new Staker comes into picture ✅
   *  - Users shouldn't be able to claim any rewards after withdrawal 
   * 
   * 3. Initiating New Stakes
   *  - Should only be called by the governance/admin ✅
   *  - Reward value passed should never be more than available Protocol_Pool_Fees in the protocol. ✅
   *  - lastUpdateTime and endPeriod should be updated accurately and stakeDuration should be increased.
   *  - If new Stake is initiated after END of running stake epoch:
   *    - Rewards should be accurate if new stake is initiated After an existing stakeDuration.
   * 
   *    - Rewards should be accurate if new stake is initiated within an existing stakeDuration.
   * 
   */

  describe("EPNS CORE V2: Stake and Claim Tests", () => {
    const CHANNEL_TYPE = 2;
    const EPOCH_DURATION = 20 * 7160 // number of blocks = 143200 
    const TEST_CHANNEL_CTX = ethers.utils.toUtf8Bytes(
      "test-channel-hello-world"
    );

    beforeEach(async function () {
        /** INITIAL SET-UP **/
      await EPNSCoreV1Proxy.connect(ADMINSIGNER).setMinPoolContribution(
        ethers.utils.parseEther('1')
        );
      await EPNSCoreV1Proxy.connect(ADMINSIGNER).setEpnsCommunicatorAddress(
        EPNSCommV1Proxy.address
      );
      await EPNSCommV1Proxy.connect(ADMINSIGNER).setEPNSCoreAddress(
        EPNSCoreV1Proxy.address
      );

       /** PUSH Token Transfers **/
      await PushToken.transfer(
        BOB,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.transfer(
        ALICE,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.transfer(
        CHARLIE,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.transfer(
        ADMIN,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.transfer(
        CHANNEL_CREATOR,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );

      await PushToken.connect(BOBSIGNER).approve(
        EPNSCoreV1Proxy.address,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.connect(ADMINSIGNER).approve(
        EPNSCoreV1Proxy.address,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.connect(ALICESIGNER).approve(
        EPNSCoreV1Proxy.address,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.connect(CHARLIESIGNER).approve(
        EPNSCoreV1Proxy.address,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      await PushToken.connect(CHANNEL_CREATORSIGNER).approve(
        EPNSCoreV1Proxy.address,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION.mul(10000)
      );
      
      await EPNSCoreV1Proxy.connect(ADMINSIGNER).addPoolFees(tokensBN(200));
      await EPNSCoreV1Proxy.connect(ADMINSIGNER).initializeStake();
      // await PushToken.connect(ALICESIGNER).setHolderDelegation(
      //   EPNSCoreV1Proxy.address,
      //   true
      // );
    });
    //*** Helper Functions - Related to Channel, Tokens and Stakes ***//
    const addPoolFees = async (signer, amount) => {
      await EPNSCoreV1Proxy.connect(signer).addPoolFees(amount);
    };

    const createChannel = async (signer) => {
      await EPNSCoreV1Proxy.connect(signer).createChannelWithPUSH(
        CHANNEL_TYPE,
        TEST_CHANNEL_CTX,
        ADD_CHANNEL_MIN_POOL_CONTRIBUTION,
        0
      );
    };

    const stakePushTokens = async (signer, amount) => {
      await EPNSCoreV1Proxy.connect(signer).stake(amount);
    };

    const getLastRewardClaimedEpoch = async(user) => {
      const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
      var userDetails = await EPNSCoreV1Proxy.userFeesInfo(user);

      const lastClaimedEpoch = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), userDetails.lastClaimedBlock.toNumber());
      return lastClaimedEpoch;
    }

    const stakeAtSingleBlock = async (stakeInfos) => {
      await ethers.provider.send("evm_setAutomine", [false]);
      await Promise.all(
        stakeInfos.map((stakeInfos) =>
          stakePushTokens(stakeInfos[0], stakeInfos[1])
        )
      );
      await network.provider.send("evm_mine");
      await ethers.provider.send("evm_setAutomine", [true]);
    };
    //*** Helper Functions - Related to Block numbers, Jump Blocks, Epochs and Rewards ***//

    const getCurrentBlock = async () => {
      const currentBlock = await ethers.provider.getBlock("latest");
      return currentBlock;
    }

    /** ⛔️ Not used currently - Prefer using passBlockNumbers **/
    const jumpToBlockNumber = async (blockNumber) => {
      blockNumber = blockNumber.toNumber();
      const currentBlock = await ethers.provider.getBlock("latest");
      const numBlockToIncrease = blockNumber - currentBlock.number;
      const blockIncreaseHex = `0x${numBlockToIncrease.toString(16)}`;
      await ethers.provider.send("hardhat_mine", [blockIncreaseHex]);
    };

    const passBlockNumers = async(blockNumber)=>{
      blockNumber = `0x${blockNumber.toString(16)}`;
      await ethers.provider.send("hardhat_mine", [blockNumber]);
    }

    const claimRewardsInSingleBlock = async (signers) => {
      await ethers.provider.send("evm_setAutomine", [false]);
      await Promise.all(
        signers.map((signer) => EPNSCoreV1Proxy.connect(signer).harvestAll())
      );
      await network.provider.send("evm_mine");
      await ethers.provider.send("evm_setAutomine", [true]);
    };

    const getUserTokenWeight = async (user, amount, atBlock) =>{
      const holderWeight = await PushToken.holderWeight(user);
      return amount.mul(atBlock - holderWeight);
    }

    const getRewardsClaimed = async (signers) => {
      return await Promise.all(
        signers.map((signer) => EPNSCoreV1Proxy.usersRewardsClaimed(signer))
      );
    };

    const getEachEpochDetails = async(user, totalEpochs) =>{
      for(i = 1; i <= totalEpochs; i++){
        var epochToTotalWeight = await EPNSCoreV1Proxy.epochToTotalStakedWeight(i);
        var epochRewardsStored = await EPNSCoreV1Proxy.epochRewards(i);
        const userEpochToStakedWeight = await EPNSCoreV1Proxy.getUserEpochToWeight(user, i);
        
        console.log('\n EACH EPOCH DETAILS ');
        console.log(`EPOCH Rewards for EPOCH ID ${i} is ${epochRewardsStored}`)
        console.log(`EPOCH to Total Weight for EPOCH ID ${i} is ${epochToTotalWeight}`)
        console.log(`userEpochToStakedWeight for EPOCH ID ${i} is ${userEpochToStakedWeight}`)
      }
    }

/** Test Cases Starts Here **/

   /* CHECKPOINTS: lastEpochRelative() function 
    * Should Reverts on overflow
    * Should calculate relative epoch numbers accurately
    * Shouldn't change epoch value if epoch "to" block number lies in same epoch boundry
    * User BOB stakes: Ensure epochIDs of lastStakedEpoch and lastClaimedEpoch are recorded accurately 
    * User BOB stakes & then Harvests: Ensure epochIDs of lastStakedEpoch and lastClaimedEpoch are updated accurately 
    * **/
    describe.skip("🟢 lastEpochRelative Tests ", function()
    {

      it("Should revert on Block number overflow", async function(){
        const genesisBlock = await getCurrentBlock()
        await passBlockNumers(2*EPOCH_DURATION);
        const futureBlock = await getCurrentBlock();

        const tx = EPNSCoreV1Proxy.lastEpochRelative(futureBlock.number, genesisBlock.number);
        await expect(tx).to.be.revertedWith("EPNSCoreV2:lastEpochRelative:: Relative Blocnumber Overflow");
      })

      it("Should calculate relative epoch numbers accurately", async function(){
        const genesisBlock = await getCurrentBlock()
        await passBlockNumers(5*EPOCH_DURATION);
        const futureBlock = await getCurrentBlock();

        const epochID = await EPNSCoreV1Proxy.lastEpochRelative(genesisBlock.number, futureBlock.number);
        await expect(epochID).to.be.equal(6);
      })

      it("Shouldn't change epoch value if '_to' block lies in same epoch boundary", async function(){
        const genesisBlock = await getCurrentBlock()
        await passBlockNumers(EPOCH_DURATION/2);
        const futureBlock = await getCurrentBlock();

        const epochID = await EPNSCoreV1Proxy.lastEpochRelative(genesisBlock.number, futureBlock.number);
        await expect(epochID).to.be.equal(1);
      })
  
      it("Should count staked EPOCH of user correctly", async function(){
        await addPoolFees(ADMINSIGNER, tokensBN(200))
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const passBlocks = 5;

        await passBlockNumers(passBlocks * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(10));

        const bobDetails_2nd = await EPNSCoreV1Proxy.userFeesInfo(BOB);
        const userLastStakedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_2nd.lastStakedBlock.toNumber());
        const userLastClaimedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_2nd.lastClaimedBlock.toNumber());

        await expect(userLastClaimedEpochId).to.be.equal(1); // Epoch 1 - since no claim done yet
        await expect(userLastStakedEpochId).to.be.equal(passBlocks + 1);
      })

      it("Should track User's Staked and Harvest block accurately", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const fiveBlocks = 5;
        const tenBlocks = 10;

        await passBlockNumers(fiveBlocks * EPOCH_DURATION);
        // Stakes Push Tokens after 5 blocks, at 6th EPOCH
        await stakePushTokens(BOBSIGNER, tokensBN(10));
        const bobDetails_afterStake = await EPNSCoreV1Proxy.userFeesInfo(BOB);
        const userLastStakedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_afterStake.lastStakedBlock.toNumber());

        await passBlockNumers(tenBlocks * EPOCH_DURATION);
        // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        const bobDetails_afterClaim = await EPNSCoreV1Proxy.userFeesInfo(BOB);
        const userLastClaimedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_afterClaim.lastClaimedBlock.toNumber());

        await expect(userLastStakedEpochId).to.be.equal(fiveBlocks + 1);
        await expect(userLastClaimedEpochId).to.be.equal(fiveBlocks + tenBlocks + 1);
      })

    });


    describe("🟢 Stake Tests ", function()
    {

    });

    describe("🟢 unStake Tests ", function()
    {

    });

    describe("🟢 calcEpochRewards Tests ", function()
    {

    });

    describe("🟢 Harvesting Rewards Tests ", function()
    {

    });
    
    describe("🟢 daoHarvest Rewards Tests ", function()
    {

    });
    /**
     * Harvest And Reward Temp Tests - To be Categorized in specific test Case boxes later
     * -- LEVEL 1 Basic Tests -- 
     * TEST CHECK-1: BOB Stakes and Harvests alone- Should get all rewards in Pool ✅
     * TEST CHECK-2: BOB & Alice Stakes(Same Amount) and Harvests together- Should get equal rewards ✅
     * TEST CHECK-3: 4 Users Stakes(Same Amount) and Harvests together- Should get equal rewards ✅
     * TEST CHECK-4: 4 Users Stakes(Same Amount) and Harvests together(Same Epoch, Diff blocks)- Last Claimer Gets More Rewards✅
     * TEST CHECKS-5: 4 Users Stakes different amount and Harvests together- Last Claimer & Major Staker Gets More Rewards ✅
     * 
     * -- LEVEL 2 Tests -- 
     * TEST CHECKS-6: 4 Users Stakes(Same Amount) & Harvests after a gap of 2 epochs each - Last Claimer should get More Rewards ✅
     * TEST CHECKS-7: 4 Users Stakes(Same Amount) after a GAP of 2 epochs each & Harvests together - Last Claimer should get More Rewards ✅
     * TEST CHECKS-8: Stakers Stakes again in same EPOCH - Claimable Reward Calculation should be accurate ✅
     * TEST CHECKS-8.1: Stakers Stakes again in Same EPOCH with other pre-existing stakers - Claimable Reward Calculation should be accurate for all ✅
     * TEST CHECKS-9: Stakers Stakes again in Different EPOCH - Claimable Reward Calculation should be accurate ✅
     * TEST CHECKS-9.1: Stakers Stakes again in Different EPOCH with pre-existing stakers - Claimable Reward Calculation should be accurate for all ✅
    */
    describe("🟢 Random Tests on Stake N Rewards-To Be Removed later", function()
    {

      it("TEST CHECK-1: BOB Stakes and Harvests alone- Should get all rewards ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const oneEpochs= 1;
        const fiveEpochs= 5;
        await passBlockNumers(oneEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(100))
      
        const bobDetails_afterStake = await EPNSCoreV1Proxy.userFeesInfo(BOB);
        const userLastStakedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_afterStake.lastStakedBlock.toNumber());

        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        // // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        const bobLastClaimedEpochId = await getLastRewardClaimedEpoch(BOB);
        //await getEachEpochDetails(BOB, 11);

        console.log('\n BOBs Details ')
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);
        console.log('\n Stake Epoch OF BOB',userLastStakedEpochId.toNumber())
        console.log(' Reward Claim EPOCH of BOB',bobLastClaimedEpochId.toNumber())
        console.log(' REWARDS OF BOB',rewards_bob.toString())
      })

      it("TEST CHECK-2: BOB & Alice Stakes(Same Amount) and Harvests together- Should get equal rewards ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const oneEpochs = 1;
        const fiveEpochs = 5;
        await passBlockNumers(oneEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(100));
        await stakePushTokens(ALICESIGNER, tokensBN(100));
      
        const bobDetails_afterStake = await EPNSCoreV1Proxy.userFeesInfo(BOB);
        const aliceDetails_afterStake = await EPNSCoreV1Proxy.userFeesInfo(ALICE);
        const bobLastStakedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_afterStake.lastStakedBlock.toNumber());
        const aliceLastStakedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), aliceDetails_afterStake.lastStakedBlock.toNumber());

        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        // // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(ALICESIGNER).harvestAll();

        const bobDetails_afterClaim = await EPNSCoreV1Proxy.userFeesInfo(BOB);
        const aliceDetails_afterClaim = await EPNSCoreV1Proxy.userFeesInfo(ALICE);
        const bobLastClaimedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), bobDetails_afterClaim.lastClaimedBlock.toNumber());
        const aliceLastClaimedEpochId = await EPNSCoreV1Proxy.lastEpochRelative(genesisEpoch.toNumber(), aliceDetails_afterClaim.lastClaimedBlock.toNumber());

        //await getEachEpochDetails(BOB, 11);

        console.log('\n BOBs Details ')
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);
        console.log('\n Stake Epoch OF BOB',bobLastStakedEpochId.toNumber())
        console.log(' Reward Claim EPOCH of BOB',bobLastClaimedEpochId.toNumber())
        console.log(' REWARDS OF BOB',rewards_bob.toString())

        console.log('\n ALICEs Details ')
        const rewards_alice = await EPNSCoreV1Proxy.usersRewardsClaimed(ALICE);
        console.log('\n Stake Epoch OF ALICE',aliceLastStakedEpochId.toNumber())
        console.log(' Reward Claim EPOCH of ALICE',aliceLastClaimedEpochId.toNumber())
        console.log(' REWARDS OF ALICE',rewards_alice.toString())
      })

      it("TEST CHECK-3: 4 Users Stakes(Same Amount) and Harvests together- Should get equal rewards ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const oneEpochs = 1;
        const fiveEpochs = 5;
        await passBlockNumers(oneEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(100));
        await stakePushTokens(ALICESIGNER, tokensBN(100));
        await stakePushTokens(CHARLIESIGNER, tokensBN(100));
        await stakePushTokens(CHANNEL_CREATORSIGNER, tokensBN(100));
      
        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        // // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(ALICESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHARLIESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHANNEL_CREATORSIGNER).harvestAll();

        //await getEachEpochDetails(BOB, 11);

        console.log('\n BOBs Details ')
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);
        console.log(' REWARDS OF BOB',rewards_bob.toString())

        console.log('\n ALICEs Details ')
        const rewards_alice = await EPNSCoreV1Proxy.usersRewardsClaimed(ALICE);
        console.log(' REWARDS OF ALICE',rewards_alice.toString())

        console.log('\n CHARLIEs Details ')
        const rewards_charlie = await EPNSCoreV1Proxy.usersRewardsClaimed(CHARLIE);
        console.log(' REWARDS OF BOB',rewards_charlie.toString())

        console.log('\n CHANNEL_CREATORs Details ')
        const rewards_channelCreator = await EPNSCoreV1Proxy.usersRewardsClaimed(CHANNEL_CREATOR);
        console.log(' REWARDS OF BOB',rewards_channelCreator.toString())


      })

      it("TEST CHECK-4: 4 Users Stakes(Same Amount) and Harvests together- Last Claimer Gets More ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const oneEpochs = 1;
        const fiveEpochs = 5;
        await passBlockNumers(oneEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(100));
        await stakePushTokens(ALICESIGNER, tokensBN(100));
        await stakePushTokens(CHARLIESIGNER, tokensBN(100));
        await stakePushTokens(CHANNEL_CREATORSIGNER, tokensBN(100));
      
        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        // // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(ALICESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHARLIESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHANNEL_CREATORSIGNER).harvestAll();

        //await getEachEpochDetails(BOB, 11);

        console.log('\n BOBs Details ')
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);
        console.log(' REWARDS OF BOB',rewards_bob.toString())

        console.log('\n ALICEs Details ')
        const rewards_alice = await EPNSCoreV1Proxy.usersRewardsClaimed(ALICE);
        console.log(' REWARDS OF ALICE',rewards_alice.toString())

        console.log('\n CHARLIEs Details ')
        const rewards_charlie = await EPNSCoreV1Proxy.usersRewardsClaimed(CHARLIE);
        console.log(' REWARDS OF BOB',rewards_charlie.toString())

        console.log('\n CHANNEL_CREATORs Details ')
        const rewards_channelCreator = await EPNSCoreV1Proxy.usersRewardsClaimed(CHANNEL_CREATOR);
        console.log(' REWARDS OF BOB',rewards_channelCreator.toString())

        await expect(rewards_alice).to.be.gt(rewards_bob);
        await expect(rewards_charlie).to.be.gt(rewards_alice);
        await expect(rewards_channelCreator).to.be.gt(rewards_charlie);
      })

      it("TEST CHECKS-5: 4 Users Stakes different amount and Harvests together- Last Claimer & Major Staker Gets More ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const oneEpochs = 2;
        const fiveEpochs = 10;
        await passBlockNumers(oneEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(100));
        await stakePushTokens(ALICESIGNER, tokensBN(200));
        await stakePushTokens(CHARLIESIGNER, tokensBN(300));
        await stakePushTokens(CHANNEL_CREATORSIGNER, tokensBN(400));
      
        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        // // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(ALICESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHARLIESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHANNEL_CREATORSIGNER).harvestAll();

        await getEachEpochDetails(BOB, 11);

        console.log('\n BOBs Details ')
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);
        console.log(' REWARDS OF BOB',rewards_bob.toString())

        console.log('\n ALICEs Details ')
        const rewards_alice = await EPNSCoreV1Proxy.usersRewardsClaimed(ALICE);
        console.log(' REWARDS OF ALICE',rewards_alice.toString())

        console.log('\n CHARLIEs Details ')
        const rewards_charlie = await EPNSCoreV1Proxy.usersRewardsClaimed(CHARLIE);
        console.log(' REWARDS OF BOB',rewards_charlie.toString())

        console.log('\n CHANNEL_CREATORs Details ')
        const rewards_channelCreator = await EPNSCoreV1Proxy.usersRewardsClaimed(CHANNEL_CREATOR);
        console.log(' REWARDS OF BOB',rewards_channelCreator.toString())

        await expect(rewards_alice).to.be.gt(rewards_bob);
        await expect(rewards_charlie).to.be.gt(rewards_alice);
        await expect(rewards_channelCreator).to.be.gt(rewards_charlie);
      })
      // Expected Result = BOB_REWARDS > Alice > Charlie > Channel_CREATOR
      it("TEST CHECKS-5.1: 4 Users Stakes different amount and Harvests together- Last Claimer & Major Staker Gets More(First Staker stakes the MOST) ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const oneEpochs = 2;
        const fiveEpochs = 10;
        await passBlockNumers(oneEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(400));
        await stakePushTokens(ALICESIGNER, tokensBN(300));
        await stakePushTokens(CHARLIESIGNER, tokensBN(200));
        await stakePushTokens(CHANNEL_CREATORSIGNER, tokensBN(100));
      
        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        // // Harvests Push Tokens after 15 blocks, at 16th EPOCH
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(ALICESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHARLIESIGNER).harvestAll();
        await EPNSCoreV1Proxy.connect(CHANNEL_CREATORSIGNER).harvestAll();

        await getEachEpochDetails(BOB, 11);

        console.log('\n BOBs Details ')
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);
        console.log(' REWARDS OF BOB',rewards_bob.toString())

        console.log('\n ALICEs Details ')
        const rewards_alice = await EPNSCoreV1Proxy.usersRewardsClaimed(ALICE);
        console.log(' REWARDS OF ALICE',rewards_alice.toString())

        console.log('\n CHARLIEs Details ')
        const rewards_charlie = await EPNSCoreV1Proxy.usersRewardsClaimed(CHARLIE);
        console.log(' REWARDS OF BOB',rewards_charlie.toString())

        console.log('\n CHANNEL_CREATORs Details ')
        const rewards_channelCreator = await EPNSCoreV1Proxy.usersRewardsClaimed(CHANNEL_CREATOR);
        console.log(' REWARDS OF BOB',rewards_channelCreator.toString())

        await expect(rewards_charlie).to.be.gt(rewards_channelCreator);
        await expect(rewards_alice).to.be.gt(rewards_charlie);
        await expect(rewards_bob).to.be.gt(rewards_alice);
      })

      it("TEST CHECKS-6: 4 Users Stakes(Same Amount) & Harvests after a gap of 2 epochs each - Last Claimer should get More Rewards ✅", async function(){
        const genesisEpoch = await EPNSCoreV1Proxy.genesisEpoch();
        const twoEpochs = 2;
        const fiveEpochs = 5;
        await passBlockNumers(twoEpochs * EPOCH_DURATION);
        await stakePushTokens(BOBSIGNER, tokensBN(100));
        await stakePushTokens(ALICESIGNER, tokensBN(100));
        await stakePushTokens(CHARLIESIGNER, tokensBN(100));
        await stakePushTokens(CHANNEL_CREATORSIGNER, tokensBN(100));
      
        // Bob Harvests after EPOCH 5+2+1 = 8
        await passBlockNumers(fiveEpochs * EPOCH_DURATION);
        await EPNSCoreV1Proxy.connect(BOBSIGNER).harvestAll();
        // Alice Harvests after EPOCH 11
        await passBlockNumers(twoEpochs * EPOCH_DURATION);
        await EPNSCoreV1Proxy.connect(ALICESIGNER).harvestAll();
        // Charlie Harvests after EPOCH 13
        await passBlockNumers(twoEpochs * EPOCH_DURATION);
        await EPNSCoreV1Proxy.connect(CHARLIESIGNER).harvestAll();
        // ChannelCreator Harvests after EPOCH 15
        await passBlockNumers(twoEpochs * EPOCH_DURATION);
        await EPNSCoreV1Proxy.connect(CHANNEL_CREATORSIGNER).harvestAll();

        const bob_ClaimedBlock = await getLastRewardClaimedEpoch(BOB);
        const rewards_bob = await EPNSCoreV1Proxy.usersRewardsClaimed(BOB);

        const alice_ClaimedBlock = await getLastRewardClaimedEpoch(ALICE);
        const rewards_alice = await EPNSCoreV1Proxy.usersRewardsClaimed(ALICE);

        const charlie_ClaimedBlock = await getLastRewardClaimedEpoch(CHARLIE);
        const rewards_charlie = await EPNSCoreV1Proxy.usersRewardsClaimed(CHARLIE);
        
        const channeCreator_ClaimedBlock = await getLastRewardClaimedEpoch(CHANNEL_CREATOR);
        const rewards_channelCreator = await EPNSCoreV1Proxy.usersRewardsClaimed(CHANNEL_CREATOR);

        await expect(rewards_alice).to.be.gt(rewards_bob);
        await expect(rewards_charlie).to.be.gt(rewards_alice);
        await expect(rewards_channelCreator).to.be.gt(rewards_charlie);

        console.log(`BOB Claimed at EPOCH-${bob_ClaimedBlock.toNumber()} and got ${rewards_bob.toString()} Rewards`)
        console.log(`ALICE Claimed at EPOCH-${alice_ClaimedBlock.toNumber()} and got ${rewards_alice.toString()} Rewards`)
        console.log(`CHARLIE Claimed at EPOCH-${charlie_ClaimedBlock.toNumber()} and got ${rewards_charlie.toString()} Rewards`)
        console.log(`CHANNEL_CREATOR Claimed at EPOCH-${channeCreator_ClaimedBlock.toNumber()} and got ${rewards_channelCreator.toString()} Rewards`)


      })

    });
/**Test Cases Ends Here **/
  });
});