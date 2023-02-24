// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {LlamaSubsFlatRateERC20} from "./LlamaSubsFlatRateERC20.sol";
import {LlamaSubsFlatRateERC20NonRefundable} from "./LlamaSubsFlatRateERC20NonRefundable.sol";
import "openzeppelin-contracts/proxy/Clones.sol";

contract LlamaSubsFactory {
    using Clones for address;

    LlamaSubsFlatRateERC20NonRefundable public immutable nonrefundableImpl;
    LlamaSubsFlatRateERC20 public immutable refundableImpl;

    event DeployFlatRateERC20(
        address deployedContract,
        address indexed owner,
        uint256 currentPeriod,
        uint256 periodDuration,
        LlamaSubsFlatRateERC20.TierInfo[] tiers
    );
    event DeployFlatRateERC20NonRefundable(
        address deployedContract,
        address indexed owner,
        LlamaSubsFlatRateERC20NonRefundable.SubInfo[] subs
    );

    constructor(
        LlamaSubsFlatRateERC20NonRefundable _nonrefundableImpl,
        LlamaSubsFlatRateERC20 _refundableImpl
    ) {
        nonrefundableImpl = _nonrefundableImpl;
        refundableImpl = _refundableImpl;
    }

    struct TierInfo {
        uint224 costPerPeriod;
        address token;
    }

    function deployFlatRateERC20(
        uint256 _currentPeriod,
        uint256 _periodDuration,
        LlamaSubsFlatRateERC20.TierInfo[] memory tiers
    ) external returns (LlamaSubsFlatRateERC20 deployedContract) {
        deployedContract = LlamaSubsFlatRateERC20(
            address(refundableImpl).clone()
        );
        deployedContract.initialize(
            msg.sender,
            _currentPeriod,
            _periodDuration,
            tiers
        );
        emit DeployFlatRateERC20(
            address(deployedContract),
            msg.sender,
            _currentPeriod,
            _periodDuration,
            tiers
        );
    }

    function deployFlatRateERC20NonRefundable(
        LlamaSubsFlatRateERC20NonRefundable.SubInfo[] memory subs
    ) external returns (LlamaSubsFlatRateERC20NonRefundable deployedContract) {
        deployedContract = LlamaSubsFlatRateERC20NonRefundable(
            address(nonrefundableImpl).clone()
        );
        deployedContract.initialize(msg.sender, subs);
        emit DeployFlatRateERC20NonRefundable(
            address(deployedContract),
            msg.sender,
            subs
        );
    }
}
