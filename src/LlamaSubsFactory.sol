// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {LlamaSubsFlatRateERC20} from "./LlamaSubsFlatRateERC20.sol";
import {LlamaSubsFlatRateERC20NonRefundable} from "./LlamaSubsFlatRateERC20NonRefundable.sol";

contract LlamaSubsFactory {
    event DeployFlatRateERC20(
        address indexed deployedContract,
        address indexed owner,
        address indexed token,
        uint256 currentPeriod,
        uint256 periodDuration
    );
    event DeployFlatRateERC20NonRefundable(
        address indexed deployedContract,
        address indexed owner,
        address indexed token
    );

    function deployFlatRateERC20(
        address _owner,
        address _token,
        uint256 _currentPeriod,
        uint256 _periodDuration
    ) external returns (LlamaSubsFlatRateERC20 deployedContract) {
        deployedContract = new LlamaSubsFlatRateERC20(
            _owner,
            _token,
            _currentPeriod,
            _periodDuration
        );
        emit DeployFlatRateERC20(
            address(deployedContract),
            _owner,
            _token,
            _currentPeriod,
            _periodDuration
        );
    }

    function deployFlatRateERC20NonRefundable(address _owner, address _token)
        external
        returns (LlamaSubsFlatRateERC20NonRefundable deployedContract)
    {
        deployedContract = new LlamaSubsFlatRateERC20NonRefundable(
            _owner,
            _token
        );
        emit DeployFlatRateERC20NonRefundable(
            address(deployedContract),
            _owner,
            _token
        );
    }
}
