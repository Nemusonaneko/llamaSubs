// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "openzeppelin-contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/utils/Strings.sol";

error INVALID_SUB();
error SUB_ALREADY_EXISTS();
error NOT_OWNER();
error NOT_OWNER_OR_WHITELISTED();
error TOKEN_NOT_ACCEPTED();

contract LlamaSubsFlatRateERC20NonRefundable is ERC1155, Initializable {
    using SafeTransferLib for ERC20;

    struct Sub {
        uint208 costOfSub;
        uint40 duration;
        uint8 disabled;
        address token;
    }

    address public owner;
    uint256 public numOfSubs;
    address constant feeCollector = 0x08a3c2A819E3de7ACa384c798269B3Ce1CD0e437;

    mapping(uint256 => Sub) public subs;
    mapping(uint256 => uint256) public newExpires;
    mapping(address => uint256) public whitelist;

    event Subscribe(
        uint256 id,
        address subscriber,
        uint56 sub,
        address token,
        uint40 expires,
        uint208 cost
    );
    event Extend(
        uint256 id,
        uint256 sub,
        address token,
        uint256 expires,
        uint208 cost
    );
    event Claim(address caller, address token, address to, uint256 amount);
    event AddSub(
        uint256 subNumber,
        uint208 costOfSub,
        uint40 duration,
        address token
    );
    event RemoveSub(uint256 subNumber);
    event AddWhitelist(address toAdd);
    event RemoveWhitelist(address toRemove);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    struct SubInfo {
        uint208 costOfSub;
        uint40 duration;
        address token;
    }

    function initialize(address _owner, SubInfo[] calldata _subs) public {
        owner = _owner;
        addSubsInternal(_subs);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function uri(uint256 id)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "https://nft.llamapay.com/LlamaSubsFlatRateERC20NonRefundable/",
                    Strings.toString(block.chainid),
                    "/",
                    Strings.toHexString(uint160(address(this)), 20),
                    "/",
                    Strings.toString(id)
                )
            );
    }

    function subscribe(address _subscriber, uint56 _sub) external {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        uint40 expires;
        unchecked {
            expires = uint40(block.timestamp + sub.duration);
        }
        uint256 id = uint256(
            bytes32(
                abi.encodePacked(uint40(expires), uint56(_sub), _subscriber)
            )
        );
        if (balanceOf[_subscriber][id] != 0) revert SUB_ALREADY_EXISTS();

        _mint(_subscriber, id, 1, "");
        ERC20(sub.token).safeTransferFrom(
            msg.sender,
            address(this),
            sub.costOfSub
        );
        emit Subscribe(
            id,
            _subscriber,
            _sub,
            sub.token,
            expires,
            sub.costOfSub
        );
    }

    function extend(uint256 _id) external {
        uint256 originalExpires = _id >> (256 - 40);
        uint256 _sub = (_id << 40) >> (256 - 40 - 56);
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.costOfSub == 0 || sub.duration == 0)
            revert INVALID_SUB();
        uint256 expires = max(
            max(newExpires[_id], originalExpires),
            block.timestamp
        );
        newExpires[_id] = expires + sub.duration;
        ERC20(sub.token).safeTransferFrom(
            msg.sender,
            address(this),
            sub.costOfSub
        );
        emit Extend(_id, _sub, sub.token, expires, sub.costOfSub);
    }

    function addSubInternal(
        uint208 _costOfSub,
        uint40 _duration,
        address _token
    ) internal {
        subs[numOfSubs] = Sub({
            costOfSub: _costOfSub,
            duration: _duration,
            disabled: 0,
            token: _token
        });
        uint256 oldNumOfSubs = numOfSubs;
        unchecked {
            ++numOfSubs;
        }
        emit AddSub(oldNumOfSubs, _costOfSub, _duration, _token);
    }

    function addSubsInternal(SubInfo[] calldata _subs) internal {
        uint256 i = 0;
        uint256 len = _subs.length;
        while (i < len) {
            addSubInternal(
                _subs[i].costOfSub,
                _subs[i].duration,
                _subs[i].token
            );
            unchecked {
                i++;
            }
        }
    }

    function addSubs(SubInfo[] calldata _subs) external onlyOwner {
        addSubsInternal(_subs);
    }

    function removeSubInternal(uint56 _sub) internal {
        Sub storage sub = subs[_sub];
        if (sub.disabled != 0 || sub.duration == 0) revert INVALID_SUB();
        subs[_sub].disabled = 1;
        emit RemoveSub(_sub);
    }

    function removeSubs(uint56[] calldata _subs) external onlyOwner {
        uint256 i = 0;
        uint256 len = _subs.length;
        while (i < len) {
            removeSubInternal(_subs[i]);
            unchecked {
                i++;
            }
        }
    }

    function claim(address _token, uint256 _amount) external {
        if (msg.sender != owner && whitelist[msg.sender] != 1)
            revert NOT_OWNER_OR_WHITELISTED();
        ERC20(_token).safeTransfer(owner, (_amount * 99) / 100);
        ERC20(_token).safeTransfer(feeCollector, _amount / 100);
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
        uint256 originalExpires = id >> (256 - 40);
        expires = max(newExpires[id], originalExpires);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
