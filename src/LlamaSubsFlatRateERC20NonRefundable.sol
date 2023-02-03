// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "openzeppelin-contracts-upgradable/contracts/proxy/utils/Initalizable.sol";

error INVALID_SUB();
error SUB_ALREADY_EXISTS();
error NOT_OWNER();
error NOT_OWNER_OR_WHITELISTED();
error TOKEN_NOT_ACCEPTED();

contract LlamaSubsFlatRateERC20NonRefundable is ERC1155, Initalizable {
    using SafeTransferLib for ERC20;

    struct Sub {
        uint208 costOfSub;
        uint40 duration;
        uint8 disabled;
    }

    address public owner;
    uint256 public numOfSubs;
    uint256 constant fee = 1;
    address constant feeCollector = 0x08a3c2A819E3de7ACa384c798269B3Ce1CD0e437;
    
    mapping(uint256 => Sub) public subs;
    mapping(uint256 => uint256) public newExpires;
    mapping(address => uint256) public whitelist;
    mapping(uint256 => mapping(address => uint256)) public acceptedTokens;

    event Subscribe(
        address subscriber,
        uint56 sub,
        address token,
        uint40 expires,
        uint208 cost
    );
    event Extend(
        uint256 id,
        uint56 sub,
        address token,
        uint40 expires,
        uint208 cost
    );
    event Claim(address caller, address token, address to, uint256 amount);
    event AddSub(uint256 subNumber, uint208 costOfSub, uint40 duration);
    event RemoveSub(uint256 subNumber);
    event AddWhitelist(address toAdd);
    event RemoveWhitelist(address toRemove);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    function initialize(address _owner) public {
        owner = _owner;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function subscribe(
        address _subscriber,
        uint56 _sub,
        address _token
    ) external {
        if (acceptedTokens[_sub][_token] == 0) revert TOKEN_NOT_ACCEPTED();
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        uint40 expires;
        unchecked {
            expires = uint40(block.timestamp + sub.duration);
        }
        uint256 id = uint256(bytes32(
            abi.encodePacked(expires, _sub, _subscriber)
        ));
        if (balanceOf[_subscriber][id] != 0) revert SUB_ALREADY_EXISTS();

        _mint(_subscriber, id, 1, "");
        ERC20(_token).safeTransferFrom(
            msg.sender,
            address(this),
            sub.costOfSub
        );
        emit Subscribe(_subscriber, _sub, _token, expires, sub.costOfSub);
    }

    function extend(uint _id, address _token) external {
        uint40 originalExpires = _id >> (256-40);
        uint56 _sub = (_id << 40) >> (256-40-56);
        Sub storage sub = subs[_sub];
        if (acceptedTokens[_sub][_token] == 0) revert TOKEN_NOT_ACCEPTED();
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        uint256 expires = max(
            max(newExpires[_id], originalExpires),
            block.timestamp
        );
        newExpires[_id] = newExpires;
        ERC20(_token).safeTransferFrom(
            msg.sender,
            address(this),
            sub.costOfSub
        );
        emit Extend(_id, _sub, _token, expires, sub.costOfSub);
    }

    function addSub(uint208 _costOfSub, uint40 _duration) external onlyOwner {
        subs[numOfSubs] = Sub({
            costOfSub: _costOfSub,
            duration: _duration,
            disabled: 0
        });
        uint256 oldNumOfSubs = numOfSubs;
        unchecked {
            ++numOfSubs;
        }
        emit AddSub(oldNumOfSubs, _costOfSub, _duration);
    }

    function removeSub(uint56 _sub) external onlyOwner {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.duration == 0) revert INVALID_SUB();
        subs[_sub].disabled = 1;
        emit RemoveSub(_sub);
    }

    function setAcceptedToken(
        uint256 _id,
        address _token,
        bool _value
    ) external onlyOwner {
        acceptedTokens[_id][_token] = _value == true ? 1 : 0;
    }

    function claim(address _token, uint256 _amount) external {
        if (msg.sender != owner && whitelist[msg.sender] != 1)
            revert NOT_OWNER_OR_WHITELISTED();
        ERC20(_token).safeTransfer(owner, (_amount * (100 - fee)) / 100);
        ERC20(_token).safeTransfer(feeCollector, (_amount * fee) / 100);
        emit Claim(msg.sender, _token, owner, _amount);
    }

    function addWhitelist(address _toAdd) external onlyOwner {
        whitelist[_toAdd] = 1;
        emit AddWhitelist(_toAdd);
    }

    function removeWhitelist(address _toRemove) external onlyOwner {
        whitelist[_toRemove] = 0;
        emit RemoveWhitelist(_toRemove);
    }

    function expiration(uint256 id) external view returns (uint256 expires) {
        uint40 originalExpires = id >> (256-40);
        expires = max(newExpires[id], expires);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
