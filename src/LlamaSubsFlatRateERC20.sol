// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import "openzeppelin-contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/utils/Strings.sol";

error INVALID_TIER();
error ALREADY_SUBBED();
error NOT_SUBBED();
error NOT_OWNER();
error NOT_OWNER_OR_WHITELISTED();
error CURRENT_PERIOD_IN_FUTURE();
error WRONG_TIER();
error SUB_DOES_NOT_EXIST();
error PERIOD_TOO_HIGH();

contract LlamaSubsFlatRateERC20 is ERC1155, Initializable {
    using SafeTransferLib for ERC20;

    struct Tier {
        uint224 costPerPeriod;
        uint88 amountOfSubs;
        uint40 disabledAt;
        address token;
    }

    struct TierInfo {
        uint224 costPerPeriod;
        address token;
    }

    address public owner;
    uint128 public currentPeriod;
    uint128 public periodDuration;
    uint256[] public activeTiers;
    mapping(uint256 => Tier) public tiers;
    mapping(uint256 => uint256) public updatedExpiration;
    mapping(uint256 => mapping(uint256 => uint256)) public subsToExpire;
    mapping(address => uint256) public whitelist;
    mapping(address => uint256) public claimables;
    mapping(address => uint24) public nonces;
    address public immutable feeCollector;

    event Subscribe(
        uint256 id,
        address subscriber,
        uint256 tier,
        uint256 durations,
        uint256 expires,
        uint256 sent
    );
    event Extend(
        uint256 id,
        uint256 tier,
        uint256 durations,
        uint256 expires,
        uint256 sent
    );
    event Unsubscribe(
        uint256 id,
        uint256 tier,
        uint256 expires,
        uint256 refund
    );
    event Claim(address caller, address to, address token, uint256 amount);
    event AddTier(uint256 tierNumber, address token, uint224 costPerPeriod);
    event RemoveTier(uint256 tierNumber, uint256 disabledAt);
    event AddWhitelist(address toAdd);
    event RemoveWhitelist(address toRemove);

    constructor(address _feeCollector){
        feeCollector = _feeCollector;
    }

    function initialize(
        address _owner,
        uint128 _currentPeriod,
        uint128 _periodDuration,
        TierInfo[] calldata _tiers
    ) public initializer {
        owner = _owner;
        currentPeriod = _currentPeriod;
        periodDuration = _periodDuration;
        if(_periodDuration > 1e12){ // 31k years
            revert PERIOD_TOO_HIGH(); // Prevent insane periods that could cause overflows later on and trap users
        }
        if (block.timestamp + uint256(_periodDuration) < uint256(_currentPeriod)) {
            revert CURRENT_PERIOD_IN_FUTURE();
        }
        addTiersInternal(_tiers);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
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
                    "https://nft.llamapay.io/LlamaSubsFlatRateERC20/",
                    Strings.toString(block.chainid),
                    "/",
                    Strings.toHexString(uint160(address(this)), 20),
                    "/",
                    Strings.toString(id)
                )
            );
    }

    /* implements this code but in O(1)
          while (block.timestamp > currentPeriod) currentPeriod += periodDuration
    */
    function getUpdatedCurrentPeriod()
        public
        view
        returns (uint256 updatedCurrentPeriod)
    {
        if(currentPeriod>block.timestamp) return currentPeriod; // Most common case for active pools
        // block.timestamp-currentPeriod >= 0 because of previous if-check
        // block.timestamp >= block.timestamp-currentPeriod
        //  -> block.timestamp >= (block.timestamp-currentPeriod)%periodDuration
        //  -> block.timestamp - (block.timestamp-currentPeriod)%periodDuration >= 0
        // thus there are no possible underflows here
        uint newCurrent = block.timestamp - (block.timestamp-uint256(currentPeriod))%periodDuration;
        if(newCurrent<block.timestamp) newCurrent+=periodDuration;
        return newCurrent;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function currentExpires(uint256 original, uint256 updated)
        internal
        pure
        returns (uint256)
    {
        return updated == 0 ? original : updated;
    }

    function subscribe(
        address _subscriber,
        uint256 _tier,
        uint256 _durations
    ) external {
        Tier storage tier = tiers[_tier];
        if (tier.disabledAt > 0 || tier.costPerPeriod == 0)
            revert INVALID_TIER();

        uint256 updatedCurrentPeriod = getUpdatedCurrentPeriod();
        uint256 expires;
        uint256 actualDurations;
        uint256 claimableThisPeriod;
        unchecked {
            actualDurations = _durations - 1; // This can underflow, but it will only affect the event
            claimableThisPeriod =
                (tier.costPerPeriod * // costPerPeriod is fixed so owner can't frontrun an increase
                    (updatedCurrentPeriod - block.timestamp)) /
                periodDuration;
            expires = updatedCurrentPeriod + (actualDurations * periodDuration); // Can overflow but user would just be rugging themselves (+ need to pay huge sums)
        }
        uint256 id = uint256(
            bytes32(
                abi.encodePacked(uint40(expires), uint32(_tier), nonces[_subscriber]++, _subscriber) // Nonce makes it impossible to create 2 subs with same id
            )
        );
        unchecked {
            subsToExpire[_tier][expires]++;
            tier.amountOfSubs++;
        }
        uint256 sendToContract = claimableThisPeriod +
            (actualDurations * uint256(tier.costPerPeriod));
        claimables[tier.token] += claimableThisPeriod;

        _mint(_subscriber, id, 1, "");
        ERC20(tier.token).safeTransferFrom(
            msg.sender,
            address(this),
            sendToContract
        );
        emit Subscribe(
            id,
            _subscriber,
            _tier,
            _durations,
            expires,
            sendToContract
        );
    }

    function extend(uint256 _id, uint256 _durations, address _owner) external {
        if(balanceOf[_owner][_id] == 0) revert SUB_DOES_NOT_EXIST();
        uint256 originalExpires = currentExpires(
            _id >> (256 - 40),
            updatedExpiration[_id]
        );
        uint256 _tier = (_id << 40) >> (256 - 32);
        Tier storage tier = tiers[_tier];
        if (tier.disabledAt != 0) revert INVALID_TIER();
        uint256 updatedCurrentPeriod = getUpdatedCurrentPeriod();
        uint256 actualDurations;
        uint256 claimableThisPeriod;
        uint256 expires;
        unchecked {
            actualDurations = _durations - 1;
            expires =
                max(originalExpires, updatedCurrentPeriod) +
                (actualDurations * periodDuration);
            if (originalExpires >= currentPeriod) { // Using currentPeriod instead of updatedCurrentPeriod purposefully
                subsToExpire[_tier][originalExpires]--;
            }
            if (originalExpires < updatedCurrentPeriod) {
                claimableThisPeriod =
                    (tier.costPerPeriod *
                        (updatedCurrentPeriod - block.timestamp)) /
                    periodDuration;
            }
            subsToExpire[_tier][expires]++;
            updatedExpiration[_id] = expires;
        }
        uint256 sendToContract = claimableThisPeriod +
            (actualDurations * uint256(tier.costPerPeriod));
        claimables[tier.token] += claimableThisPeriod;
        ERC20(tier.token).safeTransferFrom(
            msg.sender,
            address(this),
            sendToContract
        );
        emit Extend(_id, _tier, _durations, expires, sendToContract);
    }

    function unsubscribe(uint256 _id) external {
        if (balanceOf[msg.sender][_id] == 0) revert SUB_DOES_NOT_EXIST();
        uint256 originalExpires = currentExpires(
            _id >> (256 - 40),
            updatedExpiration[_id]
        );
        uint256 _tier = (_id << 40) >> (256 - 32);
        Tier storage tier = tiers[_tier];
        uint256 refund;
        uint256 updatedCurrentPeriod = getUpdatedCurrentPeriod();
        uint256 expires;
        unchecked {
            if (tier.disabledAt > 0 && originalExpires > tier.disabledAt) {
                refund =
                    ((uint256(originalExpires) - uint256(tier.disabledAt)) *
                        uint256(tier.costPerPeriod)) /
                    periodDuration;
                updatedExpiration[_id] = uint256(tier.disabledAt);
                expires = tier.disabledAt;
            } else if (originalExpires > updatedCurrentPeriod) {
                refund =
                    ((uint256(originalExpires) - updatedCurrentPeriod) *
                        uint256(tier.costPerPeriod)) /
                    periodDuration;
                subsToExpire[_tier][originalExpires]--;
                subsToExpire[_tier][updatedCurrentPeriod]++;
                updatedExpiration[_id] = updatedCurrentPeriod;
                expires = updatedCurrentPeriod;
            } else {
                expires = originalExpires;
            }
        }
        ERC20(tier.token).safeTransfer(msg.sender, refund);
        emit Unsubscribe(_id, _tier, expires, refund);
    }

    function claim(uint256 _amount, address token) external {
        if (msg.sender != owner && whitelist[msg.sender] != 1)
            revert NOT_OWNER_OR_WHITELISTED();
        _update();
        claimables[token] -= _amount;
        ERC20(token).safeTransfer(owner, (_amount * 99) / 100);
        ERC20(token).safeTransfer(
            feeCollector,
            _amount / 100
        );
        emit Claim(msg.sender, owner, token, _amount);
    }

    function addTierInternal(uint224 _costPerPeriod, address _token) internal {
        uint256 tierNumber = activeTiers.length;
        tiers[tierNumber].costPerPeriod = _costPerPeriod;
        tiers[tierNumber].token = _token;
        activeTiers.push(tierNumber);
        emit AddTier(tierNumber, _token, _costPerPeriod);
    }

    function addTiersInternal(TierInfo[] calldata _tiers) internal {
        uint256 i = 0;
        uint256 len = _tiers.length;
        while (i < len) {
            addTierInternal(_tiers[i].costPerPeriod, _tiers[i].token);
            unchecked {
                i++;
            }
        }
    }

    function addTiers(TierInfo[] calldata _tiers) external onlyOwner {
        _update();
        addTiersInternal(_tiers);
    }

    function removeTierInternal(uint256 _tierIndex) internal {
        uint256 len = activeTiers.length;
        if (_tierIndex >= len) {
            revert WRONG_TIER();
        }
        uint256 _tier = activeTiers[_tierIndex];
        uint256 last = activeTiers[len - 1];
        tiers[_tier].disabledAt = uint40(currentPeriod);
        activeTiers[_tierIndex] = last;
        activeTiers.pop();
        emit RemoveTier(_tier, currentPeriod);
    }

    function removeTiers(uint256[] calldata _tierIndexs) external onlyOwner {
        _update();
        uint256 i = 0;
        uint256 len = _tierIndexs.length;
        while (i < len) {
            removeTierInternal(_tierIndexs[i]);
            unchecked {
                i++;
            }
        }
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
        uint128 newCurrentPeriod = currentPeriod;
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
                claimables[tier.token] +=
                    uint256(tier.amountOfSubs) *
                    uint256(tier.costPerPeriod);
                delete subsToExpire[curr][newCurrentPeriod];
                unchecked {
                    ++i;
                }
            }
            unchecked {
                newCurrentPeriod += periodDuration;
            }
        }
        currentPeriod = newCurrentPeriod;
    }

    function expiration(uint256 id) external view returns (uint256 expires) {
        expires = currentExpires(id >> (256 - 40), updatedExpiration[id]);
    }

    function claimableNow(address _token)
        external
        view
        returns (uint256 claimable)
    {
        uint128 newCurrentPeriod = currentPeriod;
        uint256 len = activeTiers.length;
        claimable = claimables[_token];
        while (block.timestamp > newCurrentPeriod) {
            uint256 i = 0;
            while (i < len) {
                uint256 curr = activeTiers[i];
                Tier storage tier = tiers[curr];
                uint256 newAmountOfSubs;
                unchecked {
                    newAmountOfSubs =
                        uint256(tier.amountOfSubs) -
                        uint256(subsToExpire[curr][newCurrentPeriod]);
                }
                claimable += newAmountOfSubs * uint256(tier.costPerPeriod);
                unchecked {
                    ++i;
                }
            }
            unchecked {
                newCurrentPeriod += periodDuration;
            }
        }
    }
}
