// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;
import {LlamaSubsFlatRate} from "./LlamaSubsFlatRate.sol";

contract LlamaSubFactory {
    address owner;
    address token;
    uint256 start;
    uint256 period;
    uint128[] public tiers;

    function createFlatRate(
        address _token,
        uint256 _start,
        uint256 _period,
        uint128[] memory _tiers
    ) external returns (LlamaSubsFlatRate createdContract) {
        owner = msg.sender;
        token = _token;
        start = _start;
        period = _period;
        tiers = _tiers;
        createdContract = new LlamaSubsFlatRate();
    }
}
