// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

error INVALID_TIER();
error ALREADY_SUBBED();
error NOT_SUBBED();
error NOT_OWNER();
error INVALID_VALUE();

contract LlamaSubsFlatRateETH {
    struct Tier {
        uint128 costPerPeriod;
        uint88 amountOfSubs;
        uint40 disabledAt;
    }

    struct User {
        uint216 tier;
        uint40 expires;
    }

    address payable public owner;
    uint256 public currentPeriod;
    uint256 public periodDuration;
    uint256 public claimable;
    uint256 public numOfTiers;
    uint256[] public activeTiers;
    mapping(uint256 => Tier) public tiers;
    mapping(uint256 => mapping(uint256 => uint256)) public subsToExpire;
    mapping(address => User) public users;

    event Subscribe(
        address indexed subscriber,
        uint256 tier,
        uint256 durations,
        uint256 expires,
        uint256 sent
    );
    event Unsubscribe(address indexed subscriber, uint256 refund);
    event Extend(
        address indexed subscriber,
        uint256 durations,
        uint256 newExpiry,
        uint256 sendToContract
    );
    event Claim(uint256 amount);
    event AddTier(uint256 tierNumber, uint128 costPerPeriod);
    event RemoveTier(uint256 tierNumber);

    constructor(
        address payable _owner,
        uint256 _currentPeriod,
        uint256 _periodDuration
    ) {
        owner = _owner;
        currentPeriod = _currentPeriod;
        periodDuration = _periodDuration;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    function subscribe(uint256 _tier, uint256 _durations) external payable {
        Tier storage tier = tiers[_tier];
        if (tier.disabledAt > 0 || tier.costPerPeriod == 0)
            revert INVALID_TIER();
        if (users[msg.sender].expires > 0) revert ALREADY_SUBBED();
        _update();
        uint256 expires;
        uint256 nextPeriod;
        uint256 actualDurations;
        uint256 claimableThisPeriod;
        unchecked {
            nextPeriod = currentPeriod + periodDuration;
            claimableThisPeriod =
                (tier.costPerPeriod * block.timestamp) /
                nextPeriod;
            actualDurations = _durations - 1;
            expires = currentPeriod + (actualDurations * periodDuration);
        }
        uint256 sendToContract = claimableThisPeriod +
            (actualDurations * uint256(tier.costPerPeriod));
        if (msg.value != sendToContract) revert INVALID_VALUE();
        claimable += claimableThisPeriod;
        unchecked {
            tiers[_tier].amountOfSubs++;
            subsToExpire[_tier][expires]++;
        }
        users[msg.sender] = User({
            tier: uint216(_tier),
            expires: uint40(expires)
        });
        emit Subscribe(msg.sender, _tier, _durations, expires, sendToContract);
    }

    function unsubscribe() external {
        User storage user = users[msg.sender];
        if (user.expires == 0) revert NOT_SUBBED();
        _update();

        Tier storage tier = tiers[user.tier];
        uint256 refund;
        uint256 nextPeriod;
        unchecked {
            nextPeriod = currentPeriod + periodDuration;
            if (tier.disabledAt > 0 && user.expires > tier.disabledAt) {
                refund =
                    ((uint256(user.expires) - uint256(tier.disabledAt)) *
                        uint256(tier.costPerPeriod)) /
                    periodDuration;
            } else if (user.expires > nextPeriod) {
                refund =
                    ((uint256(user.expires) - nextPeriod) *
                        uint256(tier.costPerPeriod)) /
                    periodDuration;
                subsToExpire[user.tier][user.expires]--;
                tiers[user.tier].amountOfSubs--;
            }
        }
        delete users[msg.sender];
        SafeTransferLib.safeTransferETH(msg.sender, refund);
        emit Unsubscribe(msg.sender, refund);
    }

    function extend(uint256 _durations) external payable {
        User storage user = users[msg.sender];
        if (user.expires == 0) revert NOT_SUBBED();
        Tier storage tier = tiers[user.tier];
        if (tier.disabledAt > 0) revert INVALID_TIER();
        _update();

        uint256 newExpiry;
        uint256 nextPeriod;
        uint256 actualDurations;
        uint256 claimableThisPeriod;
        unchecked {
            nextPeriod = currentPeriod + periodDuration;
            actualDurations = _durations - 1;
            newExpiry =
                uint256(user.expires) +
                (actualDurations * periodDuration);
            if (nextPeriod > user.expires) {
                claimableThisPeriod =
                    (tier.costPerPeriod * block.timestamp) /
                    nextPeriod;
            }
        }
        uint256 sendToContract = claimableThisPeriod +
            (actualDurations * uint256(tier.costPerPeriod));
        if (msg.value != sendToContract) revert INVALID_VALUE();
        claimable += claimableThisPeriod;
        unchecked {
            subsToExpire[user.tier][newExpiry]++;
            if (user.expires > currentPeriod) {
                subsToExpire[user.tier][user.expires]--;
            }
        }
        emit Extend(msg.sender, _durations, newExpiry, sendToContract);
    }

    function claim() external onlyOwner {
        _update();
        uint256 toOwner = claimable;
        claimable = 0;
        SafeTransferLib.safeTransferETH(owner, toOwner);
        emit Claim(toOwner);
    }

    function addTier(uint128 _costPerPeriod) external onlyOwner {
        _update();
        uint256 tierNumber = numOfTiers;
        tiers[tierNumber].costPerPeriod = _costPerPeriod;
        activeTiers.push(tierNumber);
        unchecked {
            numOfTiers++;
        }
        emit AddTier(tierNumber, _costPerPeriod);
    }

    function removeTier(uint256 _tier) external onlyOwner {
        _update();
        uint256 len = activeTiers.length;
        uint256 last = activeTiers[len - 1];
        uint256 i = 0;
        while (activeTiers[i] != _tier) {
            unchecked {
                i++;
            }
        }
        uint256 nextPeriod;
        unchecked {
            nextPeriod = currentPeriod + periodDuration;
        }
        claimable +=
            uint256(tiers[_tier].costPerPeriod) *
            uint256(tiers[_tier].amountOfSubs);

        tiers[_tier].disabledAt = uint40(nextPeriod);
        activeTiers[i] = last;
        activeTiers.pop();
        emit RemoveTier(_tier);
    }

    function _update() private {
        /// This will save gas since u only update storage at the end
        uint256 newCurrentPeriod = currentPeriod;
        uint256 newClaimable = claimable;

        uint256 len = activeTiers.length;
        while (block.timestamp > newCurrentPeriod) {
            uint256 i = 0;
            while (i < len) {
                uint256 curr = activeTiers[i];
                Tier storage tier = tiers[curr];
                newClaimable +=
                    uint256(tier.amountOfSubs) *
                    uint256(tier.costPerPeriod);
                unchecked {
                    tiers[curr].amountOfSubs -= uint88(
                        subsToExpire[curr][newCurrentPeriod]
                    );
                }
                /// Free up storage
                delete subsToExpire[curr][newCurrentPeriod];
                unchecked {
                    i++;
                }
            }
            unchecked {
                /// Go to next period
                newCurrentPeriod += periodDuration;
            }
        }
        currentPeriod = newCurrentPeriod;
        claimable = newClaimable;
    }
}
