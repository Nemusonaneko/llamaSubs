// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

error INVALID_SUB();
error NOT_OWNER();
error NOT_OWNER_OR_WHITELISTED();

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
    mapping(address => uint256) public whitelist;

    event Subscribe(
        address subscriber,
        uint216 sub,
        uint40 expires,
        uint208 cost
    );
    event Claim(address caller, address to, uint256 amount);
    event AddSub(uint256 subNumber, uint208 costOfSub, uint40 duration);
    event RemoveSub(uint256 subNumber);
    event AddWhitelist(address toAdd);
    event RemoveWhitelist(address toRemove);

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
        uint40 expires;
        unchecked {
            expires = uint40(block.timestamp + sub.duration);
        }
        users[_subscriber] = User({expires: expires, sub: _sub});
        ERC20(token).safeTransferFrom(msg.sender, address(this), sub.costOfSub);
        emit Subscribe(_subscriber, _sub, expires, sub.costOfSub);
    }

    function addSub(uint208 _costOfSub, uint40 _duration) external onlyOwner {
        uint256 oldNumOfSubs = numOfSubs;
        subs[oldNumOfSubs] = Sub({
            costOfSub: _costOfSub,
            duration: _duration,
            disabled: 0
        });
        unchecked {
            ++numOfSubs;
        }
        emit AddSub(oldNumOfSubs, _costOfSub, _duration);
    }

    function removeSub(uint216 _sub) external onlyOwner {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        subs[_sub].disabled = 1;
        emit RemoveSub(_sub);
    }

    function claim(uint256 _amount) external {
        if (msg.sender != owner && whitelist[msg.sender] != 1)
            revert NOT_OWNER_OR_WHITELISTED();
        ERC20(token).safeTransfer(owner, _amount);
        emit Claim(msg.sender, owner, _amount);
    }

    function addWhitelist(address _toAdd) external onlyOwner {
        whitelist[_toAdd] = 1;
        emit AddWhitelist(_toAdd);
    }

    function removeWhitelist(address _toRemove) external onlyOwner {
        whitelist[_toRemove] = 0;
        emit RemoveWhitelist(_toRemove);
    }
}
