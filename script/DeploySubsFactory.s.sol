//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {LlamaSubsFactory} from "../src/LlamaSubsFactory.sol";
import {LlamaSubsFlatRateERC20} from "../src/LlamaSubsFlatRateERC20.sol";
import {LlamaSubsFlatRateERC20NonRefundable} from "../src/LlamaSubsFlatRateERC20NonRefundable.sol";

contract DeploySubsFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        LlamaSubsFlatRateERC20 refundable = new LlamaSubsFlatRateERC20();
        LlamaSubsFlatRateERC20NonRefundable nonrefundable = new LlamaSubsFlatRateERC20NonRefundable();
        LlamaSubsFactory factory = new LlamaSubsFactory(
            nonrefundable,
            refundable
        );
        vm.stopBroadcast();
    }
}
