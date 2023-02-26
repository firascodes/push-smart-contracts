// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

pragma experimental ABIEncoderV2;

import "../../EPNSCore/EPNSCoreV2.sol";

contract $EPNSCoreV2 is EPNSCoreV2 {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    function $lastEpochInitialized() external view returns (uint256) {
        return lastEpochInitialized;
    }

    function $lastTotalStakeEpochInitialized() external view returns (uint256) {
        return lastTotalStakeEpochInitialized;
    }

    function $oneTimeCheck() external view returns (bool) {
        return oneTimeCheck;
    }

    function $ADJUST_FOR_FLOAT() external view returns (uint256) {
        return ADJUST_FOR_FLOAT;
    }

    function $getChainId() external pure returns (uint256 ret0) {
        (ret0) = super.getChainId();
    }

    function $_returnPushTokenWeight(address _account,uint256 _amount,uint256 _atBlock) external view returns (uint256 ret0) {
        (ret0) = super._returnPushTokenWeight(_account,_amount,_atBlock);
    }

    function $_adjustUserAndTotalStake(address _user,uint256 _userWeight) external {
        super._adjustUserAndTotalStake(_user,_userWeight);
    }

    function $__Pausable_init() external {
        super.__Pausable_init();
    }

    function $__Pausable_init_unchained() external {
        super.__Pausable_init_unchained();
    }

    function $_pause() external {
        super._pause();
    }

    function $_unpause() external {
        super._unpause();
    }

    function $__Context_init() external {
        super.__Context_init();
    }

    function $__Context_init_unchained() external {
        super.__Context_init_unchained();
    }

    function $_msgSender() external view returns (address payable ret0) {
        (ret0) = super._msgSender();
    }

    function $_msgData() external view returns (bytes memory ret0) {
        (ret0) = super._msgData();
    }

    receive() external payable {}
}
