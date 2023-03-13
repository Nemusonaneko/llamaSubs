//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/utils/Address.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract FeeCollector is Ownable {
    using Address for address payable;
    using SafeTransferLib for ERC20;

    function collectETH(uint amount, address payable to) external onlyOwner {
        to.sendValue(amount);
    }

    function collectTokens(
        uint amount,
        address token,
        address to
    ) external onlyOwner {
        ERC20(token).safeTransfer(to, amount);
    }

    receive() external payable {}
}
