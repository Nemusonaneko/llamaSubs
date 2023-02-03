// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

error INVALID_TIER();
error ALREADY_SUBBED();
error NOT_SUBBED();
error NOT_OWNER();
error NOT_OWNER_OR_WHITELISTED();

contract LlamaSubsFlatRateERC20 {
    using SafeTransferLib for ERC20;

    struct Tier {
        uint128 costPerPeriod;
        uint88 amountOfSubs;
        uint40 disabledAt;
    }

    struct User {
        uint216 tier;
        uint40 expires;
    }

    address public immutable owner;
    address public immutable token;
    uint256 public currentPeriod;
    uint256 public periodDuration;
    uint256 public claimable;
    uint256 public numOfTiers;
    uint256[] public activeTiers;
    mapping(uint256 => Tier) public tiers;
    mapping(uint256 => mapping(uint256 => uint256)) public subsToExpire;
    mapping(address => User) public users;
    mapping(address => uint256) public whitelist;

    event Subscribe(
        address indexed subscriber,
        uint256 tier,
        uint256 durations,
        uint256 expires,
        uint256 sent
    );
    event Unsubscribe(address indexed subscriber, uint256 refund);
    event Claim(address caller, address to, uint256 amount);
    event AddTier(uint256 tierNumber, uint128 costPerPeriod);
    event RemoveTier(uint256 tierNumber);
    event AddWhitelist(address toAdd);
    event RemoveWhitelist(address toRemove);

    constructor(
        address _owner,
        address _token,
        uint256 _currentPeriod,
        uint256 _periodDuration
    ) {
        owner = _owner;
        token = _token;
        currentPeriod = _currentPeriod;
        periodDuration = _periodDuration;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

     function getUpdatedCurrentPeriod()
        public
        view
        returns (uint256 updatedCurrentPeriod)
    {
        return (block.timestamp + periodDuration) - (currentPeriod % periodDuration);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function subscribe(
        address _subscriber,
        uint256 _tier,
        uint256 _durations
    ) external {
        Tier storage tier = tiers[_tier];
        if (tier.disabledAt > 0 || tier.costPerPeriod == 0)
            revert INVALID_TIER();
        _update();

        User storage user = users[_subscriber];
        uint256 expires;
        uint256 actualDurations;
        uint256 claimableThisPeriod;
        unchecked {
            actualDurations = _durations - 1;
            expires =
                max(uint256(user.expires), currentPeriod) +
                (actualDurations * periodDuration);
            if (user.expires >= currentPeriod) {
                subsToExpire[user.tier][user.expires]--;
            }
            if (user.expires < currentPeriod) {
                claimableThisPeriod =
                    (tier.costPerPeriod * (currentPeriod - block.timestamp)) /
                    periodDuration;
            }
            subsToExpire[user.tier][expires]++;
        }
        uint256 sendToContract = claimableThisPeriod +
            (actualDurations * uint256(tier.costPerPeriod));
        claimable += claimableThisPeriod;
        users[_subscriber] = User({
            tier: uint216(_tier),
            expires: uint40(expires)
        });
        tier.amountOfSubs++;
        ERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            sendToContract
        );
        emit Subscribe(_subscriber, _tier, _durations, expires, sendToContract);
    }

    function unsubscribe() external {
        User storage user = users[msg.sender];
        if (user.expires == 0) revert NOT_SUBBED();
        _update();

        Tier storage tier = tiers[user.tier];
        uint256 refund;
        unchecked {
            if (tier.disabledAt > 0 && user.expires > tier.disabledAt) {
                refund =
                    ((uint256(user.expires) - uint256(tier.disabledAt)) *
                        uint256(tier.costPerPeriod)) /
                    periodDuration;
            } else if (user.expires > currentPeriod) {
                refund =
                    ((uint256(user.expires) - currentPeriod) *
                        uint256(tier.costPerPeriod)) /
                    periodDuration;
                subsToExpire[user.tier][user.expires]--;
                tiers[user.tier].amountOfSubs--;
                user.expires = uint40(currentPeriod);
            }
        }
        ERC20(token).safeTransfer(msg.sender, refund);
        emit Unsubscribe(msg.sender, refund);
    }

    function claim(uint256 _amount) external {
        if (msg.sender != owner && whitelist[msg.sender] != 1)
            revert NOT_OWNER_OR_WHITELISTED();
        _update();
        claimable -= _amount;
        ERC20(token).safeTransfer(owner, _amount);
        emit Claim(msg.sender, owner, _amount);
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

    function removeTier(uint256 _tierIndex) external onlyOwner {
        _update();
        uint256 len = activeTiers.length;
        if(_tierIndex >= len){
            revert();
        }
        uint256 _tier = activeTiers[_tierIndex];
        uint256 last = activeTiers[len - 1];
        tiers[_tier].disabledAt = uint40(currentPeriod);
        activeTiers[_tierIndex] = last;
        activeTiers.pop();
        emit RemoveTier(_tier);
    }

    function addWhitelist(address _toAdd) external onlyOwner {
        whitelist[_toAdd] = 1;
        emit AddWhitelist(_toAdd);
    }

    function removeWhitelist(address _toRemove) external onlyOwner {
        whitelist[_toRemove] = 0;
        emit RemoveWhitelist(_toRemove);
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
                unchecked {
                    tier.amountOfSubs -= uint88(
                        subsToExpire[curr][newCurrentPeriod]
                    );
                }
                newClaimable +=
                    uint256(tier.amountOfSubs) *
                    uint256(tier.costPerPeriod);
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
