// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import "solmate/tokens/ERC1155.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

error INVALID_SUB();
error SUB_ALREADY_EXISTS();
error NOT_OWNER();
error NOT_OWNER_OR_WHITELISTED();

contract LlamaSubsFlatRateERC20NonRefundable is ERC1155 {
    using SafeTransferLib for ERC20;

    struct Sub {
        uint208 costOfSub;
        uint40 duration;
        uint8 disabled;
    }

    struct Subscription {
        uint40 expires;
        uint56 sub;
        address originalOwner; // Acts as salt to prevent collisions
    }

    address public owner;
    address public immutable token;
    uint256 public numOfSubs;
    uint256 constant fee = 1;
    address constant feeCollector = 0x08a3c2A819E3de7ACa384c798269B3Ce1CD0e437;

    mapping(uint256 => Sub) public subs;
    mapping(uint => uint) public newExpires;
    mapping(address => uint256) public whitelist;

    event Subscribe(
        address subscriber,
        uint56 sub,
        uint40 expires,
        uint208 cost
    );
    event Claim(address caller, address to, uint256 amount);
    event AddSub(uint256 subNumber, uint208 costOfSub, uint40 duration);
    event RemoveSub(uint256 subNumber);
    event AddWhitelist(address toAdd);
    event RemoveWhitelist(address toRemove);

    constructor(address _owner, address _token){
        owner = _owner;
        token = _token;
    }


    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function subscribe(address _subscriber, uint56 _sub) external {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        uint40 expires;
        unchecked {
            expires = uint40(block.timestamp + sub.duration);
        }
        uint id = uint256(Subscription({expires: expires, sub: _sub, originalOwner: _subscriber}));
        if(balanceOf[_subscriber][id] != 0){
            revert SUB_ALREADY_EXISTS();
        }
        _mint(_subscriber, id, 1, "");
        ERC20(token).safeTransferFrom(msg.sender, address(this), sub.costOfSub);
        emit Subscribe(_subscriber, _sub, expires, sub.costOfSub);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function extend(address id) external {
        (uint40 originalExpires, uint56 sub) = Subscription(id);
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();

        uint expires = max(max(newExpires[id], expires), block.timestamp);
        unchecked {
            expires = uint40(expires + sub.duration);
        }
        newExpires[id] = newExpires;
        ERC20(token).safeTransferFrom(msg.sender, address(this), sub.costOfSub);
        emit Subscribe(_subscriber, _sub, expires, sub.costOfSub);
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
        emit AddSub(oldNumOfSubs, _costOfSub, _duration);
    }

    function removeSub(uint56 _sub) external onlyOwner {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.duration == 0)
            revert INVALID_SUB();
        subs[_sub].disabled = 1;
        emit RemoveSub(_sub);
    }

    function claim(uint256 _amount) external {
        if (msg.sender != owner && whitelist[msg.sender] != 1)
            revert NOT_OWNER_OR_WHITELISTED();
        ERC20(token).safeTransfer(owner, (_amount*(100-fee))/100);
        ERC20(token).safeTransfer(feeCollector, (_amount*fee)/100);
        emit Claim(msg.sender, owner, _amount);
    }

    function expiration(uint256 id) view external returns (uint expires) {
        (uint40 originalExpires) = Subscription(id);
        expires = max(newExpires[id], expires);
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
