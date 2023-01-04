// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface LlamaSubFactory {
    function owner() external view returns (address);

    function token() external view returns (address);

    function start() external view returns (uint256);

    function period() external view returns (uint256);

    function tiers() external view returns (uint128[] memory);
}

error INVALID_TIER();
error ALREADY_SUBBED();
error NOT_SUBBED();
error NOT_OWNER();

contract LlamaSubsFlatRate {
    using SafeTransferLib for ERC20;

    struct Tier {
        uint128 costPerPeriod;
        uint128 amountOfSubs;
    }

    struct User {
        uint128 tier;
        uint128 expires;
    }

    address public owner;
    address public token;
    uint256 public currentPeriod;
    uint256 public period;
    uint256 public claimable;
    Tier[] public tiers;
    mapping(address => User) public users;
    mapping(uint256 => mapping(uint256 => uint256)) public subsToExpire;

    event Subscribe(
        address indexed subscriber,
        uint256 tier,
        uint256 periods,
        uint256 expires,
        uint256 sent
    );
    event Unsubscribe(address indexed subscriber);
    event Extend(
        address indexed subscriber,
        uint256 periods,
        uint256 newExpiry
    );
    event Claim(uint256 amount);

    constructor() {
        owner = LlamaSubFactory(msg.sender).owner();
        token = LlamaSubFactory(msg.sender).token();
        currentPeriod = LlamaSubFactory(msg.sender).start();
        period = LlamaSubFactory(msg.sender).period();
        uint128[] memory tierList = LlamaSubFactory(msg.sender).tiers();
        uint256 len = tierList.length;
        uint256 i = 0;
        while (i < len) {
            tiers[i].costPerPeriod = tierList[i];
            unchecked {
                i++;
            }
        }
    }

    function subscribe(uint256 _tier, uint256 _periods) external {
        if (_tier >= tiers.length) revert INVALID_TIER();
        if (users[msg.sender].expires != 0) revert ALREADY_SUBBED();
        _update();
        uint256 expires;
        uint256 sendToContract = _periods * uint256(tiers[_tier].costPerPeriod);
        unchecked {
            expires = currentPeriod + (period * _periods);
            tiers[_tier].amountOfSubs++;
            subsToExpire[_tier][expires]++;
        }
        users[msg.sender].tier = uint128(_tier);
        users[msg.sender].expires = uint128(expires);
        ERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            sendToContract
        );
        emit Subscribe(msg.sender, _tier, _periods, expires, sendToContract);
    }

    function unsubscribe() external {
        User storage user = users[msg.sender];
        if (user.expires == 0) revert NOT_SUBBED();
        _update();

        uint256 nextPeriod;
        uint256 refund;
        unchecked {
            nextPeriod = currentPeriod + period;
        }
        /// If not already expired, then refund excess to user
        if (user.expires > nextPeriod) {
            refund =
                ((uint256(user.expires) - nextPeriod) *
                    uint256(tiers[user.tier].costPerPeriod)) /
                period;
            unchecked {
                tiers[user.tier].amountOfSubs--;
                /// Have to update subsToExpire so owner wont be underpaid on update
                subsToExpire[user.tier][user.expires]--;
            }
        }
        /// Free up storage and allows user to resub
        delete users[msg.sender];
        ERC20(token).safeTransfer(msg.sender, refund);
        emit Unsubscribe(msg.sender);
    }

    function extend(uint256 _periods) external {
        User storage user = users[msg.sender];
        if (user.expires == 0) revert NOT_SUBBED();
        _update();
        uint256 newExpiry;
        unchecked {
            newExpiry = uint256(user.expires) + _periods * period;
            subsToExpire[user.tier][newExpiry]++;
            if (user.expires > currentPeriod) {
                subsToExpire[user.tier][user.expires]--;
            }
        }
        ERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            _periods * uint256(tiers[user.tier].costPerPeriod)
        );
        emit Extend(msg.sender, _periods, newExpiry);
    }

    function claim() external {
        if (msg.sender != owner) revert NOT_OWNER();
        _update();
        uint256 toOwner = claimable;
        claimable = 0;
        ERC20(token).safeTransfer(owner, toOwner);
        emit Claim(toOwner);
    }

    function _update() private {
        /// This will save gas since u only update storage at the end
        uint256 newCurrentPeriod = currentPeriod;
        uint256 newClaimable = claimable;
        uint256 len = tiers.length;
        uint256[] memory newAmountOfSubs;
        /// This will also save gas since you dont update amountPerSub in storage
        /// every time in while loop
        uint256 i = 0;
        while (i < len) {
            newAmountOfSubs[i] = tiers[i].amountOfSubs;
            unchecked {
                i++;
            }
        }
        /// Reset for later use
        i = 0;
        /// Update Current Period until actual current period
        /// Update amountOfSubs and claimable accordingly
        while (block.timestamp > newCurrentPeriod) {
            uint256 j = 0;
            /// Update for each tier
            while (j < len) {
                Tier storage tier = tiers[j];
                unchecked {
                    /// Subtract amountOfSubs by expiring subs of current period
                    /// This will get the actual amount that are subscribed
                    newAmountOfSubs[j] -= subsToExpire[j][newCurrentPeriod];
                }
                newClaimable +=
                    newAmountOfSubs[j] *
                    uint256(tier.costPerPeriod);
                /// Free up storage
                delete subsToExpire[j][newCurrentPeriod];
                unchecked {
                    j++;
                }
            }
            unchecked {
                /// Go to next period
                newCurrentPeriod += period;
            }
        }
        /// Finally update storage
        currentPeriod = newCurrentPeriod;
        claimable = newClaimable;
        while (i < len) {
            tiers[i].amountOfSubs = uint128(newAmountOfSubs[i]);
            unchecked {
                i++;
            }
        }
    }
}
