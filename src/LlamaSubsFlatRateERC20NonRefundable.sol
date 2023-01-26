// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

error INVALID_SUB();
error NOT_OWNER();

contract LlamaSubsFlatRateERC20NonRefundable {
    using SafeTransferLib for ERC20;

    struct Sub {
        uint208 costOfSub;
        uint40 duration;
        uint8 disabled;
    }

    struct User {
        uint40 expires;
        uint216 sub;
    }

    address public immutable owner;
    address public immutable token;
    uint256 public numOfSubs;

    mapping(uint256 => Sub) public subs;
    mapping(address => User) public users;

    constructor(address _owner, address _token) {
        owner = _owner;
        token = _token;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    function subscribe(address _subscriber, uint216 _sub) external {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        users[_subscriber] = User({
            expires: uint40(block.timestamp + sub.duration),
            sub: _sub
        });
        ERC20(token).safeTransferFrom(msg.sender, owner, sub.costOfSub);
    }

    function addSub(uint208 _costOfSub, uint40 _duration) external onlyOwner {
        subs[numOfSubs] = Sub({
            costOfSub: _costOfSub,
            duration: _duration,
            disabled: 0
        });
        unchecked {
            ++numOfSubs;
        }
    }

    function removeSub(uint216 _sub) external onlyOwner {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        subs[_sub].disabled = 1;
    }
}
