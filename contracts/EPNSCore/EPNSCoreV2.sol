pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

/**
 * EPNS Core is the main protocol that deals with the imperative
 * features and functionalities like Channel Creation, pushChannelAdmin etc.
 *
 * This protocol will be specifically deployed on Ethereum Blockchain while the Communicator
 * protocols can be deployed on Multiple Chains.
 * The EPNS Core is more inclined towards the storing and handling the Channel related
 * Functionalties.
 **/
import "hardhat/console.sol";
import "./EPNSCoreStorageV1_5.sol";
import "./EPNSCoreStorageV2.sol";
import "../interfaces/IPUSH.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IEPNSCommV1.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract EPNSCoreV2 is
    Initializable,
    EPNSCoreStorageV1_5,
    PausableUpgradeable,
    EPNSCoreStorageV2
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ***************
        EVENTS
     *************** */
    event UpdateChannel(address indexed channel, bytes identity);
    event RewardsClaimed(address indexed user, uint256 rewardAmount);
    event ChannelVerified(address indexed channel, address indexed verifier);
    event ChannelVerificationRevoked(
        address indexed channel,
        address indexed revoker
    );

    event DeactivateChannel(
        address indexed channel,
        uint256 indexed amountRefunded
    );
    event ReactivateChannel(
        address indexed channel,
        uint256 indexed amountDeposited
    );
    event ChannelBlocked(address indexed channel);
    event AddChannel(
        address indexed channel,
        ChannelType indexed channelType,
        bytes identity
    );
    event ChannelNotifcationSettingsAdded(
        address _channel,
        uint256 totalNotifOptions,
        string _notifSettings,
        string _notifDescription
    );
    event AddSubGraph(address indexed channel, bytes _subGraphData);
    event TimeBoundChannelDestroyed(
        address indexed channel,
        uint256 indexed amountRefunded
    );
    event ChannelOwnershipTransfer(
        address indexed channel,
        address indexed newOwner
    );
    /* **************
        MODIFIERS
    ***************/
    modifier onlyPushChannelAdmin() {
        require(
            msg.sender == pushChannelAdmin,
            "EPNSCoreV1_5::onlyPushChannelAdmin: Caller not pushChannelAdmin"
        );
        _;
    }

    modifier onlyGovernance() {
        require(
            msg.sender == governance,
            "EPNSCoreV1_5::onlyGovernance: Caller not Governance"
        );
        _;
    }

    modifier onlyInactiveChannels(address _channel) {
        require(
            channels[_channel].channelState == 0,
            "EPNSCoreV1_5::onlyInactiveChannels: Channel already Activated"
        );
        _;
    }
    modifier onlyActivatedChannels(address _channel) {
        require(
            channels[_channel].channelState == 1,
            "EPNSCoreV1_5::onlyActivatedChannels: Channel Deactivated, Blocked or Does Not Exist"
        );
        _;
    }

    modifier onlyDeactivatedChannels(address _channel) {
        require(
            channels[_channel].channelState == 2,
            "EPNSCoreV1_5::onlyDeactivatedChannels: Channel is not Deactivated Yet"
        );
        _;
    }

    modifier onlyUnblockedChannels(address _channel) {
        require(
            ((channels[_channel].channelState != 3) &&
                (channels[_channel].channelState != 0)),
            "EPNSCoreV1_5::onlyUnblockedChannels: Channel is BLOCKED Already or Not Activated Yet"
        );
        _;
    }

    modifier onlyChannelOwner(address _channel) {
        require(
            ((channels[_channel].channelState == 1 && msg.sender == _channel) ||
                (msg.sender == pushChannelAdmin && _channel == address(0x0))),
            "EPNSCoreV1_5::onlyChannelOwner: Channel not Exists or Invalid Channel Owner"
        );
        _;
    }

    modifier onlyUserAllowedChannelType(ChannelType _channelType) {
        require(
            (_channelType == ChannelType.InterestBearingOpen ||
                _channelType == ChannelType.InterestBearingMutual ||
                _channelType == ChannelType.TimeBound ||
                _channelType == ChannelType.TokenGaited),
            "EPNSCoreV1_5::onlyUserAllowedChannelType: Channel Type Invalid"
        );

        _;
    }

    /* ***************
        INITIALIZER
    *************** */

    function initialize(
        address _pushChannelAdmin,
        address _pushTokenAddress,
        address _wethAddress,
        address _uniswapRouterAddress,
        address _lendingPoolProviderAddress,
        address _daiAddress,
        address _aDaiAddress,
        uint256 _referralCode
    ) public initializer returns (bool success) {
        // setup addresses
        pushChannelAdmin = _pushChannelAdmin;
        governance = _pushChannelAdmin; // Will be changed on-Chain governance Address later
        daiAddress = _daiAddress;
        aDaiAddress = _aDaiAddress;
        WETH_ADDRESS = _wethAddress;
        REFERRAL_CODE = _referralCode;
        PUSH_TOKEN_ADDRESS = _pushTokenAddress;
        UNISWAP_V2_ROUTER = _uniswapRouterAddress;
        lendingPoolProviderAddress = _lendingPoolProviderAddress;

        FEE_AMOUNT = 10 ether; // PUSH Amount that will be charged as Protocol Pool Fees
        MIN_POOL_CONTRIBUTION = 50 ether; // Channel's poolContribution should never go below MIN_POOL_CONTRIBUTION
        ADD_CHANNEL_MIN_FEES = 50 ether; // can never be below MIN_POOL_CONTRIBUTION

        ADJUST_FOR_FLOAT = 10**7;
        groupLastUpdate = block.number;
        groupNormalizedWeight = ADJUST_FOR_FLOAT; // Always Starts with 1 * ADJUST FOR FLOAT

        // Create Channel
        success = true;
    }

    /* ***************

    SETTER & HELPER FUNCTIONS

    *************** */
    function addSubGraph(bytes calldata _subGraphData)
        external
        onlyActivatedChannels(msg.sender)
    {
        emit AddSubGraph(msg.sender, _subGraphData);
    }

    function updateWETHAddress(address _newAddress)
        external
        onlyPushChannelAdmin
    {
        WETH_ADDRESS = _newAddress;
    }

    function updateUniswapRouterAddress(address _newAddress)
        external
        onlyPushChannelAdmin
    {
        UNISWAP_V2_ROUTER = _newAddress;
    }

    function setEpnsCommunicatorAddress(address _commAddress)
        external
        onlyPushChannelAdmin
    {
        epnsCommunicator = _commAddress;
    }

    function setGovernanceAddress(address _governanceAddress)
        external
        onlyPushChannelAdmin
    {
        governance = _governanceAddress;
    }

    function setMigrationComplete() external onlyPushChannelAdmin {
        isMigrationComplete = true;
    }

    function setFeeAmount(uint256 _newFees) external onlyGovernance {
        require(
            _newFees > 0 && _newFees < ADD_CHANNEL_MIN_FEES,
            "EPNSCoreV1_5::setFeeAmount: Fee amount must be greater than ZERO"
        );
        FEE_AMOUNT = _newFees;
    }

    function setMinPoolContribution(uint256 _newAmount) external onlyGovernance {
        require(
            _newAmount > 0,
            "EPNSCoreV1_5::setMinPoolContribution: New Pool Contribution amount must be greater than ZERO"
        );
        MIN_POOL_CONTRIBUTION = _newAmount;
    }

    function pauseContract() external onlyGovernance {
        _pause();
    }

    function unPauseContract() external onlyGovernance {
        _unpause();
    }

    /**
     * @notice Allows to set the Minimum amount threshold for Creating Channels
     *
     * @dev    Minimum required amount can never be below MIN_POOL_CONTRIBUTION
     *
     * @param _newFees new minimum fees required for Channel Creation
     **/
    function setMinChannelCreationFees(uint256 _newFees)
        external
        onlyGovernance
    {
        require(
            _newFees >= MIN_POOL_CONTRIBUTION,
            "EPNSCoreV1_5::setMinChannelCreationFees: Fees should be greater than MIN_POOL_CONTRIBUTION"
        );
        ADD_CHANNEL_MIN_FEES = _newFees;
    }

    function transferPushChannelAdminControl(address _newAdmin)
        external
        onlyPushChannelAdmin
    {
        require(
            _newAdmin != address(0),
            "EPNSCoreV1_5::transferPushChannelAdminControl: Invalid Address"
        );
        require(
            _newAdmin != pushChannelAdmin,
            "EPNSCoreV1_5::transferPushChannelAdminControl: Admin address is same"
        );
        pushChannelAdmin = _newAdmin;
    }

    /* ***********************************

        CHANNEL RELATED FUNCTIONALTIES

    **************************************/
    function getChannelState(address _channel)
        external
        view
        returns (uint256 state)
    {
        state = channels[_channel].channelState;
    }

    /**
     * @notice Allows Channel Owner to update their Channel's Details like Description, Name, Logo, etc by passing in a new identity bytes hash
     *
     * @dev  Only accessible when contract is NOT Paused
     *       Only accessible when Caller is the Channel Owner itself
     *       If Channel Owner is updating the Channel Meta for the first time:
     *       Required Fees => 50 PUSH tokens
     *
     *       If Channel Owner is updating the Channel Meta for the N time:
     *       Required Fees => (50 * N) PUSH Tokens
     *
     *       Total fees goes to PROTOCOL_POOL_FEES
     *       Updates the channelUpdateCounter
     *       Updates the channelUpdateBlock
     *       Records the Block Number of the Block at which the Channel is being updated
     *       Emits an event with the new identity for the respective Channel Address
     *
     * @param _channel     address of the Channel
     * @param _newIdentity bytes Value for the New Identity of the Channel
     * @param _amount amount of PUSH Token required for updating channel details.
     **/
    function updateChannelMeta(
        address _channel,
        bytes calldata _newIdentity,
        uint256 _amount
    ) external whenNotPaused onlyChannelOwner(_channel) {
        uint256 updateCounter = channelUpdateCounter[_channel].add(1);
        uint256 requiredFees = ADD_CHANNEL_MIN_FEES.mul(updateCounter);

        require(
            _amount >= requiredFees,
            "EPNSCoreV1_5::updateChannelMeta: Insufficient Deposit Amount"
        );
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_amount);
        channelUpdateCounter[_channel] = updateCounter;
        channels[_channel].channelUpdateBlock = block.number;

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            _channel,
            address(this),
            _amount
        );
        emit UpdateChannel(_channel, _newIdentity);
    }

    /**
     * @notice An external function that allows users to Create their Own Channels by depositing a valid amount of PUSH
     * @dev    Only allows users to Create One Channel for a specific address.
     *         Only allows a Valid Channel Type to be assigned for the Channel Being created.
     *         Validates and Transfers the amount of PUSH  from the Channel Creator to the EPNS Core Contract
     *
     * @param  _channelType the type of the Channel Being created
     * @param  _identity the bytes value of the identity of the Channel
     * @param  _amount Amount of PUSH  to be deposited before Creating the Channel
     * @param  _channelExpiryTime the expiry time for time bound channels
     **/
    function createChannelWithPUSH(
        ChannelType _channelType,
        bytes calldata _identity,
        uint256 _amount,
        uint256 _channelExpiryTime
    )
        external
        whenNotPaused
        onlyInactiveChannels(msg.sender)
        onlyUserAllowedChannelType(_channelType)
    {
        require(
            _amount >= ADD_CHANNEL_MIN_FEES,
            "EPNSCoreV1_5::_createChannelWithPUSH: Insufficient Deposit Amount"
        );
        emit AddChannel(msg.sender, _channelType, _identity);

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _createChannel(msg.sender, _channelType, _amount, _channelExpiryTime);
    }

    /**
     * @notice Migration function that allows pushChannelAdmin to migrate the previous Channel Data to this protocol
     *
     * @dev   can only be Called by the pushChannelAdmin
     *        Channel's identity is simply emitted out
     *        Channel's on-Chain details are stored by calling the "_crateChannel" function
     *        PUSH  required for Channel Creation will be PAID by pushChannelAdmin
     *
     * @param _startIndex       starting Index for the LOOP
     * @param _endIndex         Last Index for the LOOP
     * @param _channelAddresses array of address of the Channel
     * @param _channelTypeList   array of type of the Channel being created
     * @param _identityList     array of list of identity Bytes
     * @param _amountList       array of amount of PUSH  to be depositeds
     * @param  _channelExpiryTime the expiry time for time bound channels
     **/
    function migrateChannelData(
        uint256 _startIndex,
        uint256 _endIndex,
        address[] calldata _channelAddresses,
        ChannelType[] calldata _channelTypeList,
        bytes[] calldata _identityList,
        uint256[] calldata _amountList,
        uint256[] calldata _channelExpiryTime
    ) external onlyPushChannelAdmin returns (bool) {
        require(
            !isMigrationComplete,
            "EPNSCoreV1_5::migrateChannelData: Migration is already done"
        );

        require(
            (_channelAddresses.length == _channelTypeList.length) &&
                (_channelAddresses.length == _identityList.length) &&
                (_channelAddresses.length == _amountList.length) &&
                (_channelAddresses.length == _channelExpiryTime.length),
            "EPNSCoreV1_5::migrateChannelData: Unequal Arrays passed as Argument"
        );

        for (uint256 i = _startIndex; i < _endIndex; i++) {
            if (channels[_channelAddresses[i]].channelState != 0) {
                continue;
            } else {
                IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountList[i]
                );
                emit AddChannel(
                    _channelAddresses[i],
                    _channelTypeList[i],
                    _identityList[i]
                );
                _createChannel(
                    _channelAddresses[i],
                    _channelTypeList[i],
                    _amountList[i],
                    _channelExpiryTime[i]
                );
            }
        }
        return true;
    }

    /**
     * @notice Base Channel Creation Function that allows users to Create Their own Channels and Stores crucial details about the Channel being created
     * @dev    -Initializes the Channel Struct
     *         -Subscribes the Channel's Owner to Imperative EPNS Channels as well as their Own Channels
     *         - Updates the CHANNEL_POOL_FUNDS and PROTOCOL_POOL_FEES in the contract.
     *
     * @param _channel         address of the channel being Created
     * @param _channelType     The type of the Channel
     * @param _amountDeposited The total amount being deposited while Channel Creation
     * @param _channelExpiryTime the expiry time for time bound channels
     **/
    function _createChannel(
        address _channel,
        ChannelType _channelType,
        uint256 _amountDeposited,
        uint256 _channelExpiryTime
    ) private {
        uint256 poolFeeAmount = FEE_AMOUNT;
        uint256 poolFundAmount = _amountDeposited.sub(poolFeeAmount);
        //store funds in pool_funds & pool_fees
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.add(poolFundAmount);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(poolFeeAmount);

        // Calculate channel weight
        uint256 _channelWeight = poolFundAmount.mul(ADJUST_FOR_FLOAT).div(
            MIN_POOL_CONTRIBUTION
        );
        // Next create the channel and mark user as channellized
        channels[_channel].channelState = 1;
        channels[_channel].poolContribution = poolFundAmount;
        channels[_channel].channelType = _channelType;
        channels[_channel].channelStartBlock = block.number;
        channels[_channel].channelUpdateBlock = block.number;
        channels[_channel].channelWeight = _channelWeight;
        // Add to map of addresses and increment channel count
        uint256 _channelsCount = channelsCount;
        channelById[_channelsCount] = _channel;
        channelsCount = _channelsCount.add(1);

        if (_channelType == ChannelType.TimeBound) {
            require(
                _channelExpiryTime > block.timestamp,
                "EPNSCoreV1_5::createChannel: Invalid channelExpiryTime"
            );
            channels[_channel].expiryTime = _channelExpiryTime;
        }

        // Subscribe them to their own channel as well
        address _epnsCommunicator = epnsCommunicator;
        if (_channel != pushChannelAdmin) {
            IEPNSCommV1(_epnsCommunicator).subscribeViaCore(_channel, _channel);
        }

        // All Channels are subscribed to EPNS Alerter as well, unless it's the EPNS Alerter channel iteself
        if (_channel != address(0x0)) {
            IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
                address(0x0),
                _channel
            );
            IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
                _channel,
                pushChannelAdmin
            );
        }
    }

    /**
     * @notice Function that allows Channel Owners to Destroy their Time-Bound Channels
     * @dev    - Can only be called the owner of the Channel or by the EPNS Governance/Admin.
     *         - EPNS Governance/Admin can only destory a channel after 14 Days of its expriation timestamp.
     *         - Can only be called if the Channel is of type - TimeBound
     *         - Can only be called after the Channel Expiry time is up.
     *         - If Channel Owner destroys the channel after expiration, he/she recieves back refundable amount & CHANNEL_POOL_FUNDS decreases.
     *         - If Channel is destroyed by EPNS Governance/Admin, No refunds for channel owner. Refundable Push tokens are added to PROTOCOL_POOL_FEES.
     *         - Deletes the Channel completely
     *         - It transfers back refundable tokenAmount back to the USER.
     **/

    function destroyTimeBoundChannel(address _channelAddress)
        external
        whenNotPaused
        onlyActivatedChannels(_channelAddress)
    {
        Channel memory channelData = channels[_channelAddress];

        require(
            channelData.channelType == ChannelType.TimeBound,
            "EPNSCoreV1_5::destroyTimeBoundChannel: Channel is not TIME BOUND"
        );
        require(
            (msg.sender == _channelAddress &&
                channelData.expiryTime < block.timestamp) ||
                (msg.sender == pushChannelAdmin &&
                    channelData.expiryTime.add(14 days) < block.timestamp),
            "EPNSCoreV1_5::destroyTimeBoundChannel: Invalid Caller or Channel has not Expired Yet"
        );
        uint256 totalRefundableAmount = channelData.poolContribution;

        if (msg.sender != pushChannelAdmin) {
            CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(totalRefundableAmount);
            IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(
                msg.sender,
                totalRefundableAmount
            );
        } else {
            CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(totalRefundableAmount);
            PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(totalRefundableAmount);
        }
        // Unsubscribing from imperative Channels
        address _epnsCommunicator = epnsCommunicator;
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            address(0x0),
            _channelAddress
        );
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            _channelAddress,
            _channelAddress
        );
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            _channelAddress,
            pushChannelAdmin
        );
        // Decrement Channel Count and Delete Channel Completely
        channelsCount = channelsCount.sub(1);
        delete channels[_channelAddress];

        emit TimeBoundChannelDestroyed(msg.sender, totalRefundableAmount);
    }

    /** @notice - Deliminated Notification Settings string contains -> Total Notif Options + Notification Settings
     * For instance: 5+1-0+2-50-20-100+1-1+2-78-10-150
     *  5 -> Total Notification Options provided by a Channel owner
     *
     *  For Boolean Type Notif Options
     *  1-0 -> 1 stands for BOOLEAN type - 0 stands for Default Boolean Type for that Notifcation(set by Channel Owner), In this case FALSE.
     *  1-1 stands for BOOLEAN type - 1 stands for Default Boolean Type for that Notifcation(set by Channel Owner), In this case TRUE.
     *
     *  For SLIDER TYPE Notif Options
     *   2-50-20-100 -> 2 stands for SLIDER TYPE - 50 stands for Default Value for that Option - 20 is the Start Range of that SLIDER - 100 is the END Range of that SLIDER Option
     *  2-78-10-150 -> 2 stands for SLIDER TYPE - 78 stands for Default Value for that Option - 10 is the Start Range of that SLIDER - 150 is the END Range of that SLIDER Option
     *
     *  @param _notifOptions - Total Notification options provided by the Channel Owner
     *  @param _notifSettings- Deliminated String of Notification Settings
     *  @param _notifDescription - Description of each Notification that depicts the Purpose of that Notification
     *  @param _amountDeposited - Fees required for setting up channel notification settings
     **/
    function createChannelSettings(
        uint256 _notifOptions,
        string calldata _notifSettings,
        string calldata _notifDescription,
        uint256 _amountDeposited
    ) external onlyActivatedChannels(msg.sender) {
        require(
            _amountDeposited >= ADD_CHANNEL_MIN_FEES,
            "EPNSCoreV1_5::createChannelSettings: Insufficient Funds Passed"
        );

        string memory notifSetting = string(
            abi.encodePacked(
                Strings.toString(_notifOptions),
                "+",
                _notifSettings
            )
        );
        channelNotifSettings[msg.sender] = notifSetting;

        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_amountDeposited);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amountDeposited
        );
        emit ChannelNotifcationSettingsAdded(
            msg.sender,
            _notifOptions,
            notifSetting,
            _notifDescription
        );
    }

    /**
     * @notice Allows Channel Owner to Deactivate his/her Channel for any period of Time. Channels Deactivated can be Activated again.
     * @dev    - Function can only be Called by Already Activated Channels
     *         - Calculates the totalRefundableAmount for the Channel Owner.
     *         - The function deducts MIN_POOL_CONTRIBUTION from refundAble amount to ensure that channel's weight & poolContribution never becomes ZERO.
     *         - Updates the State of the Channel(channelState) and the New Channel Weight in the Channel's Struct
     *         - In case, the Channel Owner wishes to reactivate his/her channel, they need to Deposit at least the Minimum required PUSH  while reactivating.
     **/

    function deactivateChannel()
        external
        whenNotPaused
        onlyActivatedChannels(msg.sender)
    {
        Channel storage channelData = channels[msg.sender];

        uint256 minPoolContribution = MIN_POOL_CONTRIBUTION;
        uint256 totalRefundableAmount = channelData.poolContribution.sub(
            minPoolContribution
        );

        uint256 _newChannelWeight = minPoolContribution
            .mul(ADJUST_FOR_FLOAT)
            .div(minPoolContribution);

        channelData.channelState = 2;
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(totalRefundableAmount);
        channelData.channelWeight = _newChannelWeight;
        channelData.poolContribution = minPoolContribution;

        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(
            msg.sender,
            totalRefundableAmount
        );

        emit DeactivateChannel(msg.sender, totalRefundableAmount);
    }

    /**
     * @notice Allows Channel Owner to Reactivate his/her Channel again.
     * @dev    - Function can only be called by previously Deactivated Channels
     *         - Channel Owner must Depost at least minimum amount of PUSH  to reactivate his/her channel.
     *         - Deposited PUSH amount is distributed between CHANNEL_POOL_FUNDS and PROTOCOL_POOL_FEES
     *         - Calculation of the new Channel Weight and poolContribution is performed and stored
     *         - Updates the State of the Channel(channelState) in the Channel's Struct.
     * @param _amount Amount of PUSH to be deposited
     **/

    function reactivateChannel(uint256 _amount)
        external
        whenNotPaused
        onlyDeactivatedChannels(msg.sender)
    {
        require(
            _amount >= ADD_CHANNEL_MIN_FEES,
            "EPNSCoreV1_5::reactivateChannel: Insufficient Funds Passed for Channel Reactivation"
        );

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        uint256 poolFeeAmount = FEE_AMOUNT;
        uint256 poolFundAmount = _amount.sub(poolFeeAmount);
        //store funds in pool_funds & pool_fees
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.add(poolFundAmount);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(poolFeeAmount);

        Channel storage channelData = channels[msg.sender];

        uint256 _newPoolContribution = channelData.poolContribution.add(
            poolFundAmount
        );
        uint256 _newChannelWeight = _newPoolContribution
            .mul(ADJUST_FOR_FLOAT)
            .div(MIN_POOL_CONTRIBUTION);

        channelData.channelState = 1;
        channelData.poolContribution = _newPoolContribution;
        channelData.channelWeight = _newChannelWeight;

        emit ReactivateChannel(msg.sender, _amount);
    }

    /**
     * @notice ALlows the pushChannelAdmin to Block any particular channel Completely.
     *
     * @dev    - Can only be called by pushChannelAdmin
     *         - Can only be Called for Activated Channels
     *         - Can only Be Called for NON-BLOCKED Channels
     *
     *         - Updates channel's state to BLOCKED ('3')
     *         - Decreases the Channel Count
     *         - Since there is no refund, the channel's poolContribution is added to PROTOCOL_POOL_FEES and Removed from CHANNEL_POOL_FUNDS
     *         - Emit 'ChannelBlocked' Event
     * @param _channelAddress Address of the Channel to be blocked
     **/

    function blockChannel(address _channelAddress)
        external
        whenNotPaused
        onlyPushChannelAdmin
        onlyUnblockedChannels(_channelAddress)
    {
        uint256 minPoolContribution = MIN_POOL_CONTRIBUTION;
        Channel storage channelData = channels[_channelAddress];
        // add channel's currentPoolContribution to PoolFees - (no refunds if Channel is blocked)
        // Decrease CHANNEL_POOL_FUNDS by currentPoolContribution
        uint256 currentPoolContribution = channelData.poolContribution.sub(
            minPoolContribution
        );
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(currentPoolContribution);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(currentPoolContribution);

        uint256 _newChannelWeight = minPoolContribution
            .mul(ADJUST_FOR_FLOAT)
            .div(minPoolContribution);

        channelsCount = channelsCount.sub(1);
        channelData.channelState = 3;
        channelData.channelWeight = _newChannelWeight;
        channelData.channelUpdateBlock = block.number;
        channelData.poolContribution = minPoolContribution;

        emit ChannelBlocked(_channelAddress);
    }

    /**
     * @notice    Function designed to allow transfer of channel ownership
     * @dev       Can be triggered only by a channel owner. Transfers all channel date to a new owner and deletes the old channel owner details.
     *
     * @param    _channelAddress Address of the channel that needs to change its ownership
     * @param    _newChannelAddress Address of the new channel owner
     * @param    _amountDeposited Fee amount deposited for ownership transfer
     * @return   success returns true after a successful execution of the function.
     **/
    function transferChannelOwnership(
        address _channelAddress,
        address _newChannelAddress,
        uint256 _amountDeposited
    ) external whenNotPaused onlyActivatedChannels(msg.sender) returns (bool) {
        require(
            _newChannelAddress != address(0) &&
                channels[_newChannelAddress].channelState == 0,
            "EPNSCoreV1_5::transferChannelOwnership: Invalid address for new channel owner"
        );
        require(
            _amountDeposited >= ADD_CHANNEL_MIN_FEES,
            "EPNSCoreV1_5::transferChannelOwnership: Insufficient Funds Passed for Ownership Transfer Reactivation"
        );
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            _channelAddress,
            address(this),
            _amountDeposited
        );

        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_amountDeposited);
        Channel memory channelData = channels[_channelAddress];
        channels[_newChannelAddress] = channelData;

        // Subscribe newChannelOwner address to important channels
        address _epnsCommunicator = epnsCommunicator;
        IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
            _newChannelAddress,
            _newChannelAddress
        );

        IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
            address(0x0),
            _newChannelAddress
        );
        IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
            _newChannelAddress,
            pushChannelAdmin
        );

        // Unsubscribing pushChannelAdmin from old Channel
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            _channelAddress,
            pushChannelAdmin
        );

        delete channels[_channelAddress];
        emit ChannelOwnershipTransfer(_channelAddress, _newChannelAddress);
        return true;
    }

    /* **************
    => CHANNEL VERIFICATION FUNCTIONALTIES <=
    *************** */

    /**
     * @notice    Function is designed to tell if a channel is verified or not
     * @dev       Get if channel is verified or not
     * @param    _channel Address of the channel to be Verified
     * @return   verificationStatus  Returns 0 for not verified, 1 for primary verification, 2 for secondary verification
     **/
    function getChannelVerfication(address _channel)
        public
        view
        returns (uint8 verificationStatus)
    {
        address verifiedBy = channels[_channel].verifiedBy;
        bool logicComplete = false;

        // Check if it's primary verification
        if (
            verifiedBy == pushChannelAdmin ||
            _channel == address(0x0) ||
            _channel == pushChannelAdmin
        ) {
            // primary verification, mark and exit
            verificationStatus = 1;
        } else {
            // can be secondary verification or not verified, dig deeper
            while (!logicComplete) {
                if (verifiedBy == address(0x0)) {
                    verificationStatus = 0;
                    logicComplete = true;
                } else if (verifiedBy == pushChannelAdmin) {
                    verificationStatus = 2;
                    logicComplete = true;
                } else {
                    // Upper drill exists, go up
                    verifiedBy = channels[verifiedBy].verifiedBy;
                }
            }
        }
    }

    function batchVerification(
        uint256 _startIndex,
        uint256 _endIndex,
        address[] calldata _channelList
    ) external onlyPushChannelAdmin returns (bool) {
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            verifyChannel(_channelList[i]);
        }
        return true;
    }

    function batchRevokeVerification(
        uint256 _startIndex,
        uint256 _endIndex,
        address[] calldata _channelList
    ) external onlyPushChannelAdmin returns (bool) {
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            unverifyChannel(_channelList[i]);
        }
        return true;
    }

    /**
     * @notice    Function is designed to verify a channel
     * @dev       Channel will be verified by primary or secondary verification, will fail or upgrade if already verified
     * @param    _channel Address of the channel to be Verified
     **/
    function verifyChannel(address _channel)
        public
        onlyActivatedChannels(_channel)
    {
        // Check if caller is verified first
        uint8 callerVerified = getChannelVerfication(msg.sender);
        require(
            callerVerified > 0,
            "EPNSCoreV1_5::verifyChannel: Caller is not verified"
        );

        // Check if channel is verified
        uint8 channelVerified = getChannelVerfication(_channel);
        require(
            channelVerified == 0 || msg.sender == pushChannelAdmin,
            "EPNSCoreV1_5::verifyChannel: Channel already verified"
        );

        // Verify channel
        channels[_channel].verifiedBy = msg.sender;

        // Emit event
        emit ChannelVerified(_channel, msg.sender);
    }

    /**
     * @notice    Function is designed to unverify a channel
     * @dev       Channel who verified this channel or Push Channel Admin can only revoke
     * @param    _channel Address of the channel to be unverified
     **/
    function unverifyChannel(address _channel) public {
        require(
            channels[_channel].verifiedBy == msg.sender ||
                msg.sender == pushChannelAdmin,
            "EPNSCoreV1_5::unverifyChannel: Only channel who verified this or Push Channel Admin can revoke"
        );

        // Unverify channel
        channels[_channel].verifiedBy = address(0x0);

        // Emit Event
        emit ChannelVerificationRevoked(_channel, msg.sender);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /*** Core-v2: Stake n Claim Experiment starts here ***/

    // Structs & State variables

    uint256 public genesisEpoch;                // Block number at which Stakig starts
    uint256 lastEpochInitialized;               // The last EPOCH ID initialized with the respective epoch rewards
    uint256 lastTotalStakeEpochInitialized;     // The last EPOCH ID initialized with the respective total staked weight
    uint256 public epochDuration;               // 20 * number of blocks per day(7160) ~ 20 day approx
    uint256 public totalStakedWeight;           // Total token weight staked in Protocol at any given time 
    uint256 public lastTotalStakedBlock;        // The last block number stake/unstake took place
    uint256 public previouslySetEpochRewards;   // Amount of rewards set in last initialized epoch
    
    //@notice: Stores all user's staking details
    struct UserFessInfo {
      uint256 stakedAmount;
      uint256 stakedWeight;

      uint256 lastStakedBlock;
      uint256 lastClaimedBlock;

      mapping(uint256 => uint256) epochToUserStakedWeight;
    }
    // @notice: Stores all the individual epoch rewards
    mapping (uint256 => uint256) public epochRewards; 
    // @notice: Stores User's Fees Details 
    mapping (address => UserFessInfo) public userFeesInfo;
    // @notice: Stores the total staked weight at a specific epoch.
    mapping(uint256 => uint256) public epochToTotalStakedWeight;

   /**
     * @notice Function to return User's Push Holder weight based on amount being staked & current block number 
    **/
    function _returnPushTokenWeight(address _account, uint _amount, uint _atBlock) internal view returns (uint) {
      return _amount.mul(_atBlock.sub(IPUSH(PUSH_TOKEN_ADDRESS).holderWeight(_account)));
    }
    /**
     * @notice Returns the epoch ID based on the start and end block numbers passed as input 
    **/
    function lastEpochRelative(uint256 _from, uint256 _to) public view returns (uint256) {
        require(_to >= _from, "EPNSCoreV2:lastEpochRelative:: Relative Blocnumber Overflow");
        return uint256((_to - _from) / epochDuration + 1);
    }

    /**
     * @notice Calculates and returns the claimable reward amount for a user at a given EPOCH ID.
     * @dev    Formulae for reward calculation:
     *         rewards = ( userStakedWeight at Epoch(N) * avalailable rewards at EPOCH(N) ) / totalStakedWeight at EPOCH(N)
    **/
    function calculateEpochRewards(uint256 _epochId) public view returns(uint256 rewards) {
        rewards = userFeesInfo[msg.sender].epochToUserStakedWeight[_epochId].mul(epochRewards[_epochId]).div(epochToTotalStakedWeight[_epochId]);
    }
    /**
     * @notice Function to initialize the staking procedure in Core contract
     * @dev    Requires caller to deposit/stake 1 PUSH token to ensure staking pool is never zero.
    **/
    function initializeStake() external{
        require(genesisEpoch == 0, "EPNSCoreV2::initializeStake: Already Initialized");
        genesisEpoch = block.number; 
        epochDuration = 20 * 7156;
        lastEpochInitialized = genesisEpoch;
        lastTotalStakedBlock = genesisEpoch;

        IERC20(PUSH_TOKEN_ADDRESS).approve(address(this), 1e18);
        _stake(msg.sender, 1e18);
    }

   /**
     * @notice Function to allow users to stake in the protocol
     * @dev    Records total Amount staked so far by a particular user
     *         Triggers weight adjustents functions
     * @param  _amount represents amount of tokens to be staked
    **/
    function stake(uint256 _amount) external {
      _stake(msg.sender, _amount);
    }

    function _stake(address _staker, uint256 _amount) private {
        uint256 userWeight = _returnPushTokenWeight(_staker, _amount, block.number);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(msg.sender, address(this), _amount);

        userFeesInfo[_staker].stakedAmount = userFeesInfo[_staker].stakedAmount + _amount;
        userFeesInfo[_staker].lastClaimedBlock = 
            userFeesInfo[_staker].lastClaimedBlock == 0 ? genesisEpoch : userFeesInfo[_staker].lastClaimedBlock;
        

    
       // Adjust user and total rewards, piggyback method
        _adjustUserAndTotalStake(_staker, userWeight);
    }

   /**
     * @notice Function to allow users to Unstake from the protocol
     * @dev    Allows stakers to claim rewards before unstaking their tokens
     *         Triggers weight adjustents functions
     *         Allows users to unstake all amount at once
    **/
    function unstake() external {
        require(userFeesInfo[msg.sender].stakedAmount > 0, "EPNSCoreV2::unstake: Caller is not a staker");
        // Before unstaking, reset holder weight
        IPUSH(PUSH_TOKEN_ADDRESS).resetHolderWeight(msg.sender);
     
        harvestAll();
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, userFeesInfo[msg.sender].stakedAmount);
      
        // Adjust user and total rewards, piggyback method
         _adjustUserAndTotalStake(msg.sender, -userFeesInfo[msg.sender].stakedWeight);

        userFeesInfo[msg.sender].stakedAmount = 0;
        userFeesInfo[msg.sender].stakedWeight = 0;
        userFeesInfo[msg.sender].lastClaimedBlock = block.number; 
    }

    /**
     * @notice Allows users to harvest/claim their earned rewards from the protocol
     * @dev    Takes in the current block number as an arg - calculates reward till the current block number
     *         Rewards are calculated and added for all epochs between, user's lastClaimedEpoch and current epoch Id
    **/
    function harvestAll() public {
      harvestTill(block.number);
    }

    function harvestTill(uint256 _tillBlockNumber) public {

    
      // Before harvesting, reset holder weight
      IPUSH(PUSH_TOKEN_ADDRESS).resetHolderWeight(msg.sender);
      _adjustUserAndTotalStake(msg.sender, 0);
      
      uint256 currentEpoch = lastEpochRelative(genesisEpoch, _tillBlockNumber);   
     
      uint256 lastClaimedEpoch = lastEpochRelative(genesisEpoch, userFeesInfo[msg.sender].lastClaimedBlock); 
     
      uint256 rewards = 0;
      for(uint i = lastClaimedEpoch-1; i < currentEpoch; i++) { //@audit-info - changed lastClaimedEpoch to lastClaimedEpoch-1 - and then rewards work
        uint256 claimableReward = calculateEpochRewards(i);
        rewards = rewards.add(calculateEpochRewards(i));
      }
      usersRewardsClaimed[msg.sender] = usersRewardsClaimed[msg.sender].add(rewards);
      userFeesInfo[msg.sender].lastClaimedBlock = _tillBlockNumber;
      IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, rewards);
    }

    function harvestInPeriod(uint256 _startepoch, uint256 _endepoch) external {
      IPUSH(PUSH_TOKEN_ADDRESS).resetHolderWeight(msg.sender);
      _adjustUserAndTotalStake(msg.sender, 0);

      uint256 lastClaimedEpoch = lastEpochRelative(genesisEpoch, userFeesInfo[msg.sender].lastClaimedBlock);
      uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);   
      require(_startepoch == lastClaimedEpoch,"EPNSCoreV2::harvest::epoch should be sequential without repetation");
      require(currentEpoch >= _endepoch,"EPNSCoreV2::harverst::cannot harvest future epoch");

      uint256 rewards = 0;
      for(uint i = _startepoch; i < _endepoch; i++) { 
        uint256 claimableReward = calculateEpochRewards(i);
        rewards = rewards.add(claimableReward);
      }
      usersRewardsClaimed[msg.sender] = usersRewardsClaimed[msg.sender].add(rewards);
      
      // set the lastClaimedBlock = blocknumer at the endof `_endepoch`
      // TODO: peer reiview this part
      uint256 _epoch_to_block_number = genesisEpoch + _endepoch.sub(1) * epochDuration;
      userFeesInfo[msg.sender].lastClaimedBlock = _epoch_to_block_number;
      IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, rewards);
    }

    /**
     * @notice Allows Push Admin to harvest/claim the earned rewards for its stake in the protocol
     * @dev    only accessible by Push Admin - Similar to harvestTill() function
    **/
    function daoHarvest() external onlyPushChannelAdmin(){ //@audit-info - Need to be reviewed
        uint256 weightContract = userFeesInfo[address(this)].stakedWeight;
        IPUSH(PUSH_TOKEN_ADDRESS).resetHolderWeight(address(this));
        _adjustUserAndTotalStake(address(this), 0);

        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);
        uint256 lastClaimedEpoch = lastEpochRelative(genesisEpoch, userFeesInfo[address(this)].lastClaimedBlock);
        
        uint256 rewards = 0;
        for(uint i = lastClaimedEpoch; i < currentEpoch; i++) {
                rewards = rewards.add(calculateEpochRewards(i));
        }

        usersRewardsClaimed[address(this)] = usersRewardsClaimed[address(this)].add(rewards);
        userFeesInfo[address(this)].lastClaimedBlock = block.number;

    }
        
     // FOR TEST - To Be Reviewed - //

    /**
     * @notice  This functions helps in adjustment of user's as well as totalWeigts, both of which are imperative for reward calculation at a particular epoch.
     * @dev     Enables adjustments of user's stakedWeight, totalStakedWeight, epochToTotalStakedWeight as well as epochToTotalStakedWeight.
     *          triggers _setupEpochsReward() to adjust rewards for every epoch till the current epoch
     *          
     *          Includes 2 main cases of weight adjustments
     *          1st Case: User stakes for the very first time:
     *              - Simply update userFeesInfo, totalStakedWeight and epochToTotalStakedWeight of currentEpoch
     * 
     *          2nd Case: User is NOT staking for first time - 2 Subcases
     *              2.1 Case: User stakes again but in Same Epoch
     *                  - Increase user's stake and totalStakedWeight
     *                  - Record the epochToUserStakedWeight for that epoch
     *                  - Record the epochToTotalStakedWeight of that epoch
     *      
     *              2.2 Case: - User stakes again but in different Epoch
     *                  - Update the epochs between lastStakedEpoch & (currentEpoch - 1) with the old staked weight amounts
     *                  - While updating epochs between lastStaked & current Epochs, if any epoch has zero value for totalStakedWeight, update it with current totalStakedWeight value of the protocol 
     *                  - For currentEpoch, initialize the epoch id with updated weight values for epochToUserStakedWeight & epochToTotalStakedWeight
     */
    function _adjustUserAndTotalStake(address _user, uint256 _userWeight) internal {
        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);
        _setupEpochsRewardAndWeights(_userWeight, currentEpoch);

        // Initiating 1st Case: User stakes for first time
        if(userFeesInfo[_user].stakedWeight == 0){
            userFeesInfo[_user].stakedWeight = _userWeight;
        }
        else{
            // Initiating 2.1 Case: User stakes again but in Same Epoch
            uint256 lastStakedEpoch = lastEpochRelative(genesisEpoch, userFeesInfo[_user].lastStakedBlock);
            if(currentEpoch == lastStakedEpoch){
                userFeesInfo[_user].stakedWeight = userFeesInfo[_user].stakedWeight + _userWeight;
            }
            else{
            // Initiating 2.2 Case: User stakes again but in Different Epoch
                uint256 lastTotalStakedEpoch = lastEpochRelative(genesisEpoch, lastTotalStakedBlock);

                for(uint i = lastStakedEpoch - 1; i < currentEpoch; i++){  // @audit -> "uint i = lastStakedEpoch" changed to "uint i = lastStakedEpoch -1"
                    if (i != currentEpoch - 1) {
                        userFeesInfo[_user].epochToUserStakedWeight[i] = userFeesInfo[_user].stakedWeight;
                    }
                    else{
                        userFeesInfo[_user].stakedWeight = userFeesInfo[_user].stakedWeight + _userWeight;
                        userFeesInfo[_user].epochToUserStakedWeight[i] = userFeesInfo[_user].stakedWeight;
                    }
                }
            }
        }

        if(_userWeight != 0){
            userFeesInfo[_user].lastStakedBlock = block.number;
            lastTotalStakedBlock = block.number;
        }
    }

        /**
     * @notice Internal function that allows setting up the rewards for specific EPOCH IDs
     * @dev    Initializes (sets reward) for every epoch ID that falls between the lastEpochInitialized and currentEpoch
     *         Reward amount for specific EPOCH Ids depends on newly available Protocol_Pool_Fees. 
                - If no new fees was accumulated, rewards for particular epoch ids can be zero
                - Records the Pool_Fees value used as rewards.
                - Records the last epoch id whose rewards were set.
     */
    function _setupEpochsRewardAndWeights(uint256 _userWeight, uint256 _currentEpoch) private{
        uint256 _lastEpochInitiliazed = lastEpochRelative(genesisEpoch, lastEpochInitialized);
        // Setting up Epoch Based Rewards
        if(_currentEpoch > _lastEpochInitiliazed || _currentEpoch == 1){
            uint256 availableRewardsPerEpoch = (PROTOCOL_POOL_FEES - previouslySetEpochRewards);
            epochRewards[_currentEpoch - 1] += availableRewardsPerEpoch; // @audit - we store rewards in previous epoch but userStakedWeight in currentEpoch - FIXED in harvestAll() function Line 1069

            lastEpochInitialized = block.number;
            previouslySetEpochRewards = PROTOCOL_POOL_FEES; 
        }
        // Setting up Epoch Based TotalWeight
        if(lastTotalStakeEpochInitialized == 0 || lastTotalStakeEpochInitialized == _currentEpoch){
                epochToTotalStakedWeight[_currentEpoch] += _userWeight;
                epochToTotalStakedWeight[_currentEpoch - 1] += _userWeight;
        }else{
                for(uint256 i = lastTotalStakeEpochInitialized + 1; i < _currentEpoch-1; i++ ){
                    if(epochToTotalStakedWeight[i] == 0){
                        epochToTotalStakedWeight[i] = epochToTotalStakedWeight[lastTotalStakeEpochInitialized];
                    }
                }
                epochToTotalStakedWeight[_currentEpoch] = epochToTotalStakedWeight[lastTotalStakeEpochInitialized] + _userWeight;
                epochToTotalStakedWeight[_currentEpoch - 1] = epochToTotalStakedWeight[lastTotalStakeEpochInitialized] + _userWeight;
        }
        lastTotalStakeEpochInitialized = _currentEpoch;
     }

    /** TEMP Functions - Will be removed before Deployment - */
    /**
     * Owner can add pool_fees at any given time - Could be a TEMP-FUNCTION
    **/
    function addPoolFees(uint256 _rewardAmount) external onlyPushChannelAdmin() {
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(msg.sender, address(this), _rewardAmount);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_rewardAmount);
    }

    function getUserEpochToWeight(address _user, uint256 _epochId) public view returns(uint result){
        result = userFeesInfo[_user].epochToUserStakedWeight[_epochId];
     }

}
