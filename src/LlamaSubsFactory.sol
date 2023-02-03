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
        address indexed deployedContract,
        address indexed owner,
        address indexed token,
        uint256 currentPeriod,
        uint256 periodDuration
    );
    event DeployFlatRateERC20NonRefundable(
        address indexed deployedContract,
        address indexed token
    );

    constructor(
        LlamaSubsFlatRateERC20NonRefundable _nonrefundableImpl,
        LlamaSubsFlatRateERC20 _refundableImpl
    ) {
        nonrefundableImpl = _nonrefundableImpl;
        refundableImpl = _refundableImpl;
    }

    function deployFlatRateERC20(
        address _token,
        uint256 _currentPeriod,
        uint256 _periodDuration
    ) external returns (LlamaSubsFlatRateERC20 deployedContract) {
        deployedContract = LlamaSubsFlatRateERC20(
            address(refundableImpl).clone()
        );
        deployedContract.initialize(
            msg.sender,
            _token,
            _currentPeriod,
            _periodDuration
        );
        emit DeployFlatRateERC20(
            address(deployedContract),
            msg.sender,
            _token,
            _currentPeriod,
            _periodDuration
        );
    }

    function deployFlatRateERC20NonRefundable()
        external
        returns (LlamaSubsFlatRateERC20NonRefundable deployedContract)
    {
        deployedContract = LlamaSubsFlatRateERC20NonRefundable(
            address(nonrefundableImpl).clone()
        );
        deployedContract.initialize(msg.sender);
        emit DeployFlatRateERC20NonRefundable(
            address(deployedContract),
            msg.sender
        );
    }
}
