// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    DomainId,
    ScoreSetId,
    RequestId,
    PublisherId,
    BidId,
    ScoreSetStatus,
    BidSelection,
    RequestStatus,
    BidStatus,
    Publisher,
    ScoreSetMeta,
    Entry,
    ScoreRequest,
    Bid,
    LostBidder
} from "./Types.sol";
import {IWalletScore} from "./IWalletScore.sol";

/// @title WalletScoreV1
/// @notice Multi-domain wallet score registry with competitive bidding for score publication.
contract WalletScoreV1 is IWalletScore, Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    // ============ Constants ============

    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER");

    // ============ Storage ============

    // Domain storage
    mapping(DomainId => string) private _domainMetadataUri;
    mapping(DomainId => bool) private _domainExists;

    // Publisher storage
    mapping(PublisherId => Publisher) private _publishers;
    mapping(address => PublisherId) private _addressToPublisher;
    uint256 private _nextPublisherId;

    // Score set storage
    mapping(ScoreSetId => ScoreSetMeta) private _scoreSetMeta;
    mapping(ScoreSetId => Entry[]) private _scoreSetEntries;
    mapping(ScoreSetId => mapping(address => uint256)) private _scoreSetRanks; // wallet → 1-based rank
    uint256 private _nextScoreSetId;

    // Request & bidding storage
    mapping(RequestId => ScoreRequest) private _requests;
    mapping(RequestId => BidId[]) private _requestBids;
    mapping(BidId => Bid) private _bids;
    uint256 private _nextRequestId;
    uint256 private _nextBidId;

    // Bond storage
    mapping(PublisherId => uint256) private _publisherBonds;
    mapping(PublisherId => uint256) private _publisherActiveBidCount;
    uint256 private _minPublisherBond;

    // Denylist parameters
    uint256 private _denylistBaseDuration;
    uint256 private _denylistPerLostBidder;
    uint256 private _denylistValueDivisor;

    // Treasury & withdrawable
    uint256 private _treasuryBalance;
    mapping(address => uint256) private _withdrawable;

    // Domain → latest published score set tracking for efficient lookup
    mapping(DomainId => ScoreSetId[]) private _domainScoreSets;

    // ============ Constructor & Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _nextPublisherId = 1;
        _nextScoreSetId = 1;
        _nextRequestId = 1;
        _nextBidId = 1;

        // Default denylist parameters
        _denylistBaseDuration = 1 days;
        _denylistPerLostBidder = 1 hours;
        _denylistValueDivisor = 1 ether; // 1 hour per ether of lost value
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============ Modifiers ============

    modifier onlyPublisherOwner(PublisherId id) {
        if (PublisherId.unwrap(_addressToPublisher[msg.sender]) != PublisherId.unwrap(id)) {
            revert NotPublisherOrAdmin(id);
        }
        _;
    }

    modifier onlyPublisherOwnerOrAdmin(PublisherId id) {
        bool isOwner = PublisherId.unwrap(_addressToPublisher[msg.sender]) == PublisherId.unwrap(id);
        bool isAdmin = hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (!isOwner && !isAdmin) {
            revert NotPublisherOrAdmin(id);
        }
        _;
    }

    // ============ Admin Functions ============

    /// @inheritdoc IWalletScore
    function registerDomain(DomainId domainId, string calldata metadataUri)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_domainExists[domainId]) {
            revert DomainAlreadyExists(domainId);
        }
        _domainExists[domainId] = true;
        _domainMetadataUri[domainId] = metadataUri;
        emit DomainRegistered(domainId, metadataUri);
    }

    /// @inheritdoc IWalletScore
    function updateDomainMetadata(DomainId domainId, string calldata metadataUri)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!_domainExists[domainId]) {
            revert DomainNotFound(domainId);
        }
        _domainMetadataUri[domainId] = metadataUri;
        emit DomainMetadataUpdated(domainId, metadataUri);
    }

    /// @inheritdoc IWalletScore
    function registerPublisher(address addr, string calldata metadataUri)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (PublisherId)
    {
        if (PublisherId.unwrap(_addressToPublisher[addr]) != 0) {
            revert PublisherAddressAlreadyRegistered(addr);
        }

        PublisherId id = PublisherId.wrap(_nextPublisherId++);
        _publishers[id] = Publisher({currentAddress: addr, metadataUri: metadataUri, active: true, denylistUntil: 0});
        _addressToPublisher[addr] = id;

        _grantRole(PUBLISHER_ROLE, addr);

        emit PublisherRegistered(id, addr, metadataUri);
        return id;
    }

    /// @inheritdoc IWalletScore
    function updatePublisherAddress(PublisherId id, address newAddr) external override onlyPublisherOwnerOrAdmin(id) {
        Publisher storage pub = _publishers[id];
        if (pub.currentAddress == address(0)) {
            revert PublisherNotFound(id);
        }
        if (PublisherId.unwrap(_addressToPublisher[newAddr]) != 0) {
            revert PublisherAddressAlreadyRegistered(newAddr);
        }

        address oldAddr = pub.currentAddress;

        // Update reverse lookup
        _addressToPublisher[oldAddr] = PublisherId.wrap(0);
        _addressToPublisher[newAddr] = id;

        // Update publisher
        pub.currentAddress = newAddr;

        // Transfer role
        _revokeRole(PUBLISHER_ROLE, oldAddr);
        _grantRole(PUBLISHER_ROLE, newAddr);

        emit PublisherAddressUpdated(id, oldAddr, newAddr);
    }

    /// @inheritdoc IWalletScore
    function updatePublisherMetadata(PublisherId id, string calldata metadataUri)
        external
        override
        onlyPublisherOwnerOrAdmin(id)
    {
        Publisher storage pub = _publishers[id];
        if (pub.currentAddress == address(0)) {
            revert PublisherNotFound(id);
        }
        pub.metadataUri = metadataUri;
        emit PublisherMetadataUpdated(id, metadataUri);
    }

    /// @inheritdoc IWalletScore
    function deactivatePublisher(PublisherId id) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        Publisher storage pub = _publishers[id];
        if (pub.currentAddress == address(0)) {
            revert PublisherNotFound(id);
        }
        pub.active = false;
        _revokeRole(PUBLISHER_ROLE, pub.currentAddress);
        emit PublisherDeactivated(id);
    }

    /// @inheritdoc IWalletScore
    function setMinPublisherBond(uint256 amount) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _minPublisherBond = amount;
    }

    /// @inheritdoc IWalletScore
    function setDenylistParams(uint256 baseDuration, uint256 perLostBidder, uint256 valueDivisor)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _denylistBaseDuration = baseDuration;
        _denylistPerLostBidder = perLostBidder;
        _denylistValueDivisor = valueDivisor;
    }

    /// @inheritdoc IWalletScore
    function withdrawTreasury(address to, uint256 amount) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > _treasuryBalance) {
            revert InsufficientTreasuryBalance(amount, _treasuryBalance);
        }
        _treasuryBalance -= amount;
        (bool success,) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed(to, amount);
        }
    }

    // ============ Publisher Bond Functions ============

    /// @inheritdoc IWalletScore
    function depositBond() external payable override {
        PublisherId id = _addressToPublisher[msg.sender];
        if (PublisherId.unwrap(id) == 0) {
            revert PublisherNotFound(id);
        }
        Publisher storage pub = _publishers[id];
        if (!pub.active) {
            revert PublisherNotActive(id);
        }

        _publisherBonds[id] += msg.value;
        emit BondDeposited(id, msg.value, _publisherBonds[id]);
    }

    /// @inheritdoc IWalletScore
    function withdrawBond(uint256 amount) external override {
        PublisherId id = _addressToPublisher[msg.sender];
        if (PublisherId.unwrap(id) == 0) {
            revert PublisherNotFound(id);
        }

        uint256 balance = _publisherBonds[id];
        if (amount > balance) {
            revert InsufficientBondBalance(amount, balance);
        }

        // Check no active bids
        if (_publisherActiveBidCount[id] > 0) {
            revert CannotWithdrawWithActiveBids(id);
        }

        uint256 remaining = balance - amount;
        // Allow full withdrawal (deactivating effectively) or maintain minimum
        if (remaining > 0 && remaining < _minPublisherBond) {
            revert BondBelowMinimum(remaining, _minPublisherBond);
        }

        _publisherBonds[id] = remaining;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed(msg.sender, amount);
        }

        emit BondWithdrawn(id, amount, remaining);
    }

    /// @inheritdoc IWalletScore
    function getPublisherBond(PublisherId id) external view override returns (uint256) {
        return _publisherBonds[id];
    }

    // ============ Publisher Score Set Functions ============

    /// @inheritdoc IWalletScore
    function createScoreSet(DomainId domainId, uint256 scoreTimestamp)
        external
        override
        onlyRole(PUBLISHER_ROLE)
        returns (ScoreSetId)
    {
        if (!_domainExists[domainId]) {
            revert DomainNotFound(domainId);
        }

        PublisherId publisherId = _addressToPublisher[msg.sender];

        ScoreSetId id = ScoreSetId.wrap(_nextScoreSetId++);
        _scoreSetMeta[id] = ScoreSetMeta({
            domainId: domainId,
            publisher: publisherId,
            scoreTimestamp: scoreTimestamp,
            minRank: 0,
            maxRank: 0,
            status: ScoreSetStatus.Draft,
            merkleRoot: bytes32(0)
        });

        emit ScoreSetCreated(id, domainId, publisherId);
        return id;
    }

    /// @inheritdoc IWalletScore
    function addScoresToScoreSet(ScoreSetId id, uint256 startRank, Entry[] calldata entries) external override {
        ScoreSetMeta storage meta = _scoreSetMeta[id];
        if (ScoreSetId.unwrap(id) == 0 || meta.scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }
        if (meta.status != ScoreSetStatus.Draft) {
            revert ScoreSetNotDraft(id);
        }

        PublisherId publisherId = _addressToPublisher[msg.sender];
        if (PublisherId.unwrap(publisherId) != PublisherId.unwrap(meta.publisher)) {
            revert NotScoreSetOwner(id);
        }

        if (startRank == 0 || entries.length == 0) {
            revert InvalidRankRange(startRank, entries.length);
        }

        // Add entries
        Entry[] storage scoreEntries = _scoreSetEntries[id];

        // Validate startRank matches next expected rank
        uint256 expectedStartRank = scoreEntries.length + 1;
        if (startRank != expectedStartRank) {
            revert InvalidRankRange(startRank, entries.length);
        }

        for (uint256 i = 0; i < entries.length; i++) {
            scoreEntries.push(entries[i]);
            _scoreSetRanks[id][entries[i].wallet] = startRank + i;
        }

        // Update min/max rank
        if (meta.minRank == 0) {
            meta.minRank = startRank;
        }
        meta.maxRank = startRank + entries.length - 1;
    }

    /// @inheritdoc IWalletScore
    function publishScoreSet(ScoreSetId id) external override {
        ScoreSetMeta storage meta = _scoreSetMeta[id];
        if (ScoreSetId.unwrap(id) == 0 || meta.scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }
        if (meta.status != ScoreSetStatus.Draft) {
            revert ScoreSetNotDraft(id);
        }

        PublisherId publisherId = _addressToPublisher[msg.sender];
        if (PublisherId.unwrap(publisherId) != PublisherId.unwrap(meta.publisher)) {
            revert NotScoreSetOwner(id);
        }

        meta.status = ScoreSetStatus.Published;

        // Add to domain's score set list for efficient lookup
        _domainScoreSets[meta.domainId].push(id);

        uint256 entryCount = _scoreSetEntries[id].length;
        emit ScoreSetPublished(id, entryCount, meta.minRank, meta.maxRank);
    }

    // ============ Requester Functions ============

    /// @inheritdoc IWalletScore
    function createRequest(
        DomainId domainId,
        address[] calldata wallets,
        uint256 startRank,
        uint256 rankCount,
        uint256 minScoreTimestamp,
        uint256 maxScoreTimestamp,
        uint256 quotingDeadline,
        uint256 fulfillmentDeadline,
        BidSelection selectionMode
    ) external payable override returns (RequestId) {
        if (!_domainExists[domainId]) {
            revert DomainNotFound(domainId);
        }

        // Validate: either wallets or rank range, not both empty
        if (wallets.length == 0 && rankCount == 0) {
            revert InvalidRequestParams();
        }

        // Validate deadlines
        if (quotingDeadline <= block.timestamp || fulfillmentDeadline <= quotingDeadline) {
            revert InvalidDeadlines(quotingDeadline, fulfillmentDeadline);
        }

        RequestId id = RequestId.wrap(_nextRequestId++);

        _requests[id] = ScoreRequest({
            requester: msg.sender,
            domainId: domainId,
            wallets: wallets,
            startRank: startRank,
            rankCount: rankCount,
            minScoreTimestamp: minScoreTimestamp,
            maxScoreTimestamp: maxScoreTimestamp,
            quotingDeadline: quotingDeadline,
            fulfillmentDeadline: fulfillmentDeadline,
            maxBudget: msg.value,
            selectionMode: selectionMode,
            status: RequestStatus.Quoting,
            currentBid: BidId.wrap(0)
        });

        emit RequestCreated(id, msg.sender, domainId, msg.value);
        return id;
    }

    /// @inheritdoc IWalletScore
    function cancelRequest(RequestId id) external override {
        ScoreRequest storage req = _requests[id];
        if (req.requester == address(0)) {
            revert RequestNotFound(id);
        }
        if (req.requester != msg.sender) {
            revert NotRequester(id);
        }
        if (req.status != RequestStatus.Quoting && req.status != RequestStatus.Selecting) {
            revert RequestNotCancellable(id, req.status);
        }

        req.status = RequestStatus.Cancelled;

        // Refund deposit
        if (req.maxBudget > 0) {
            _withdrawable[req.requester] += req.maxBudget;
        }

        // Release any pending bids
        BidId[] storage bidIds = _requestBids[id];
        for (uint256 i = 0; i < bidIds.length; i++) {
            Bid storage bid = _bids[bidIds[i]];
            if (bid.status == BidStatus.Pending) {
                bid.status = BidStatus.Superseded;
                _publisherActiveBidCount[bid.publisher]--;
            }
        }

        emit RequestCancelled(id);
    }

    // ============ Publisher Bidding Functions ============

    /// @inheritdoc IWalletScore
    function submitBid(RequestId requestId, uint256 price, uint256 promisedDuration)
        external
        override
        onlyRole(PUBLISHER_ROLE)
        returns (BidId)
    {
        ScoreRequest storage req = _requests[requestId];
        if (req.requester == address(0)) {
            revert RequestNotFound(requestId);
        }
        if (req.status != RequestStatus.Quoting) {
            revert RequestNotInQuotingPhase(requestId, req.status);
        }
        if (block.timestamp >= req.quotingDeadline) {
            revert RequestNotInQuotingPhase(requestId, req.status);
        }

        PublisherId publisherId = _addressToPublisher[msg.sender];
        Publisher storage pub = _publishers[publisherId];

        // Check denylist
        if (pub.denylistUntil > block.timestamp) {
            revert PublisherIsDenylisted(publisherId, pub.denylistUntil);
        }

        // Check bond
        if (_publisherBonds[publisherId] < _minPublisherBond) {
            revert InsufficientBond(publisherId, _minPublisherBond, _publisherBonds[publisherId]);
        }

        // Check price
        if (price > req.maxBudget) {
            revert PriceExceedsBudget(price, req.maxBudget);
        }

        // Check timing: quotingDeadline + promisedDuration must be < fulfillmentDeadline
        if (req.quotingDeadline + promisedDuration >= req.fulfillmentDeadline) {
            revert PromisedDurationExceedsDeadline(promisedDuration, req.fulfillmentDeadline - req.quotingDeadline);
        }

        BidId bidId = BidId.wrap(_nextBidId++);
        _bids[bidId] = Bid({
            requestId: requestId,
            publisher: publisherId,
            price: price,
            promisedDuration: promisedDuration,
            submittedAt: block.timestamp,
            selectedAt: 0,
            status: BidStatus.Pending
        });

        _requestBids[requestId].push(bidId);
        _publisherActiveBidCount[publisherId]++;

        emit BidSubmitted(bidId, requestId, publisherId, price, promisedDuration);
        return bidId;
    }

    // ============ Settlement Functions ============

    /// @inheritdoc IWalletScore
    function advanceRequest(RequestId id) external override {
        ScoreRequest storage req = _requests[id];
        if (req.requester == address(0)) {
            revert RequestNotFound(id);
        }

        // Terminal states - no-op
        if (
            req.status == RequestStatus.Fulfilled || req.status == RequestStatus.Failed
                || req.status == RequestStatus.Cancelled
        ) {
            return;
        }

        // Still in quoting period
        if (req.status == RequestStatus.Quoting && block.timestamp < req.quotingDeadline) {
            return;
        }

        // Transition from Quoting to Selecting
        if (req.status == RequestStatus.Quoting && block.timestamp >= req.quotingDeadline) {
            req.status = RequestStatus.Selecting;
        }

        // If Assigned, check if current bidder's deadline expired
        if (req.status == RequestStatus.Assigned) {
            Bid storage currentBid = _bids[req.currentBid];
            uint256 deadline = currentBid.selectedAt + currentBid.promisedDuration;

            if (block.timestamp <= deadline) {
                // Current bidder still has time
                return;
            }

            // Current bidder failed - slash and denylist
            _handleBidderFailure(id, req.currentBid);
            req.status = RequestStatus.Selecting;
        }

        // In Selecting state, try to select next valid bidder
        if (req.status == RequestStatus.Selecting) {
            BidId nextBidId = _selectNextBidder(id);

            if (BidId.unwrap(nextBidId) != 0) {
                // Found valid bidder
                Bid storage nextBid = _bids[nextBidId];
                nextBid.status = BidStatus.Selected;
                nextBid.selectedAt = block.timestamp;
                req.currentBid = nextBidId;
                req.status = RequestStatus.Assigned;

                emit BidSelected(id, nextBidId, nextBid.publisher);
            } else {
                // No valid bidders left - fail request
                req.status = RequestStatus.Failed;

                // Refund requester
                if (req.maxBudget > 0) {
                    _withdrawable[req.requester] += req.maxBudget;
                }

                emit RequestFailed(id);
            }
        }
    }

    /// @inheritdoc IWalletScore
    function fulfillRequest(RequestId id, ScoreSetId scoreSetId) external override {
        ScoreRequest storage req = _requests[id];
        if (req.requester == address(0)) {
            revert RequestNotFound(id);
        }
        if (req.status != RequestStatus.Assigned) {
            revert RequestNotAssigned(id, req.status);
        }

        Bid storage currentBid = _bids[req.currentBid];
        PublisherId publisherId = _addressToPublisher[msg.sender];

        if (PublisherId.unwrap(publisherId) != PublisherId.unwrap(currentBid.publisher)) {
            revert NotCurrentBidder(id, publisherId, currentBid.publisher);
        }

        // Check deadline
        uint256 deadline = currentBid.selectedAt + currentBid.promisedDuration;
        if (block.timestamp > deadline) {
            revert FulfillmentDeadlineExceeded(id, deadline, block.timestamp);
        }

        // Verify score set covers the request
        if (!_scoreSetCoversRequest(scoreSetId, id)) {
            revert ScoreSetDoesNotCoverRequest(scoreSetId, id);
        }

        // Success - update states
        currentBid.status = BidStatus.Won;
        req.status = RequestStatus.Fulfilled;

        // Pay publisher
        uint256 payout = currentBid.price;
        _withdrawable[_publishers[publisherId].currentAddress] += payout;

        // Refund excess to requester
        uint256 excess = req.maxBudget - payout;
        if (excess > 0) {
            _withdrawable[req.requester] += excess;
        }

        // Release other pending bids
        _releasePendingBids(id);

        // Decrement active bid count for winner
        _publisherActiveBidCount[publisherId]--;

        emit RequestFulfilled(id, scoreSetId, publisherId, payout);
    }

    // ============ Internal Settlement Helpers ============

    function _handleBidderFailure(RequestId requestId, BidId failedBidId) internal {
        Bid storage failedBid = _bids[failedBidId];
        PublisherId failedPublisher = failedBid.publisher;

        // Calculate lost bidders
        (LostBidder[] memory lostBidders, uint256 totalLostValue) = _calculateLostBidders(requestId, failedBidId);

        // Calculate slash amount (for now, use fixed percentage of bond or price)
        uint256 slashAmount = _calculateSlashAmount(failedBid.price);
        if (slashAmount > _publisherBonds[failedPublisher]) {
            slashAmount = _publisherBonds[failedPublisher];
        }
        _publisherBonds[failedPublisher] -= slashAmount;

        // Calculate denylist duration
        uint256 denylistDuration = _calculateDenylistDuration(lostBidders.length, totalLostValue);
        uint256 denylistUntil = block.timestamp + denylistDuration;
        _publishers[failedPublisher].denylistUntil = denylistUntil;

        // Select next valid bidder for slash distribution
        BidId nextBidId = _selectNextBidder(requestId);

        // Distribute slash
        _distributeSlash(requestId, slashAmount, lostBidders, nextBidId);

        // Update failed bid status
        failedBid.status = BidStatus.Failed;
        _publisherActiveBidCount[failedPublisher]--;

        emit BidderFailed(requestId, failedBidId, failedPublisher, slashAmount, denylistUntil);
        emit PublisherDenylisted(failedPublisher, denylistUntil);
    }

    function _calculateLostBidders(RequestId requestId, BidId failedBidId)
        internal
        view
        returns (LostBidder[] memory, uint256)
    {
        ScoreRequest storage req = _requests[requestId];
        Bid storage failedBid = _bids[failedBidId];
        BidId[] storage bidIds = _requestBids[requestId];

        // Count eligible lost bidders first
        uint256 count = 0;
        for (uint256 i = 0; i < bidIds.length; i++) {
            if (BidId.unwrap(bidIds[i]) == BidId.unwrap(failedBidId)) continue;

            Bid storage bid = _bids[bidIds[i]];
            if (bid.status != BidStatus.Pending) continue;

            // Was valid when failed bidder was selected
            bool wasValid = failedBid.selectedAt + bid.promisedDuration < req.fulfillmentDeadline;
            // Now invalid
            bool nowInvalid = block.timestamp + bid.promisedDuration >= req.fulfillmentDeadline;

            if (wasValid && nowInvalid) {
                count++;
            }
        }

        LostBidder[] memory lostBidders = new LostBidder[](count);
        uint256 totalValue = 0;
        uint256 idx = 0;

        for (uint256 i = 0; i < bidIds.length; i++) {
            if (BidId.unwrap(bidIds[i]) == BidId.unwrap(failedBidId)) continue;

            Bid storage bid = _bids[bidIds[i]];
            if (bid.status != BidStatus.Pending) continue;

            bool wasValid = failedBid.selectedAt + bid.promisedDuration < req.fulfillmentDeadline;
            bool nowInvalid = block.timestamp + bid.promisedDuration >= req.fulfillmentDeadline;

            if (wasValid && nowInvalid) {
                lostBidders[idx] = LostBidder({bidId: bidIds[i], quotedPrice: bid.price});
                totalValue += bid.price;
                idx++;
            }
        }

        return (lostBidders, totalValue);
    }

    function _calculateSlashAmount(uint256 bidPrice) internal pure returns (uint256) {
        // Slash 50% of bid price (configurable in future versions)
        return bidPrice / 2;
    }

    function _calculateDenylistDuration(uint256 lostBidderCount, uint256 totalLostValue)
        internal
        view
        returns (uint256)
    {
        uint256 duration = _denylistBaseDuration;
        duration += lostBidderCount * _denylistPerLostBidder;
        if (_denylistValueDivisor > 0) {
            duration += totalLostValue / _denylistValueDivisor;
        }
        return duration;
    }

    function _distributeSlash(
        RequestId requestId,
        uint256 slashAmount,
        LostBidder[] memory lostBidders,
        BidId nextBidId
    ) internal {
        uint256 toTreasury;
        uint256 toLostBidders;
        uint256 toNext;

        if (lostBidders.length > 0) {
            toTreasury = (slashAmount * 20) / 100;
            toLostBidders = (slashAmount * 50) / 100;
            toNext = slashAmount - toTreasury - toLostBidders; // 30%

            // Distribute to lost bidders proportionally, credit to bond
            uint256 totalQuoted = 0;
            for (uint256 i = 0; i < lostBidders.length; i++) {
                totalQuoted += lostBidders[i].quotedPrice;
            }

            uint256 distributed = 0;
            for (uint256 i = 0; i < lostBidders.length; i++) {
                uint256 share;
                if (i == lostBidders.length - 1) {
                    // Last one gets remainder to avoid rounding issues
                    share = toLostBidders - distributed;
                } else {
                    share = (toLostBidders * lostBidders[i].quotedPrice) / totalQuoted;
                }
                _publisherBonds[_bids[lostBidders[i].bidId].publisher] += share;
                distributed += share;
            }
        } else {
            // No lost bidders: 2:3 split (40% treasury, 60% next/requester)
            toTreasury = (slashAmount * 40) / 100;
            toNext = slashAmount - toTreasury; // 60%
            toLostBidders = 0;
        }

        _treasuryBalance += toTreasury;

        if (BidId.unwrap(nextBidId) != 0) {
            _publisherBonds[_bids[nextBidId].publisher] += toNext;
        } else {
            _withdrawable[_requests[requestId].requester] += toNext;
        }

        emit SlashDistributed(requestId, toTreasury, toLostBidders, toNext);
    }

    function _selectNextBidder(RequestId requestId) internal view returns (BidId) {
        ScoreRequest storage req = _requests[requestId];
        BidId[] storage bidIds = _requestBids[requestId];

        BidId bestBidId = BidId.wrap(0);
        uint256 bestValue = type(uint256).max;

        for (uint256 i = 0; i < bidIds.length; i++) {
            Bid storage bid = _bids[bidIds[i]];

            // Only consider pending bids
            if (bid.status != BidStatus.Pending) continue;

            // Check if still valid (can complete before fulfillment deadline)
            if (block.timestamp + bid.promisedDuration >= req.fulfillmentDeadline) continue;

            // Check if publisher is not denylisted
            if (_publishers[bid.publisher].denylistUntil > block.timestamp) continue;

            // Check if publisher still has sufficient bond
            if (_publisherBonds[bid.publisher] < _minPublisherBond) continue;

            // Selection based on mode
            uint256 compareValue;
            if (req.selectionMode == BidSelection.Cheapest) {
                compareValue = bid.price;
            } else {
                compareValue = bid.promisedDuration;
            }

            if (compareValue < bestValue) {
                bestValue = compareValue;
                bestBidId = bidIds[i];
            }
        }

        return bestBidId;
    }

    function _releasePendingBids(RequestId requestId) internal {
        BidId[] storage bidIds = _requestBids[requestId];
        for (uint256 i = 0; i < bidIds.length; i++) {
            Bid storage bid = _bids[bidIds[i]];
            if (bid.status == BidStatus.Pending) {
                bid.status = BidStatus.Superseded;
                _publisherActiveBidCount[bid.publisher]--;
            }
        }
    }

    function _scoreSetCoversRequest(ScoreSetId scoreSetId, RequestId requestId) internal view returns (bool) {
        ScoreSetMeta storage meta = _scoreSetMeta[scoreSetId];
        ScoreRequest storage req = _requests[requestId];

        // Check domain matches
        if (DomainId.unwrap(meta.domainId) != DomainId.unwrap(req.domainId)) {
            return false;
        }

        // Check published
        if (meta.status != ScoreSetStatus.Published) {
            return false;
        }

        // Check timestamp in range
        if (meta.scoreTimestamp < req.minScoreTimestamp || meta.scoreTimestamp > req.maxScoreTimestamp) {
            return false;
        }

        // Check coverage
        if (req.wallets.length > 0) {
            // Must cover all requested wallets
            for (uint256 i = 0; i < req.wallets.length; i++) {
                if (_scoreSetRanks[scoreSetId][req.wallets[i]] == 0) {
                    return false;
                }
            }
        } else {
            // Must cover requested rank range
            if (meta.minRank > req.startRank || meta.maxRank < req.startRank + req.rankCount - 1) {
                return false;
            }
        }

        return true;
    }

    // ============ Query Functions ============

    /// @inheritdoc IWalletScore
    function getDomainMetadataUri(DomainId id) external view override returns (string memory) {
        if (!_domainExists[id]) {
            revert DomainNotFound(id);
        }
        return _domainMetadataUri[id];
    }

    /// @inheritdoc IWalletScore
    function getPublisher(PublisherId id) external view override returns (Publisher memory) {
        if (_publishers[id].currentAddress == address(0)) {
            revert PublisherNotFound(id);
        }
        return _publishers[id];
    }

    /// @inheritdoc IWalletScore
    function getPublisherByAddress(address addr) external view override returns (PublisherId, Publisher memory) {
        PublisherId id = _addressToPublisher[addr];
        if (PublisherId.unwrap(id) == 0) {
            revert PublisherNotFound(id);
        }
        return (id, _publishers[id]);
    }

    /// @inheritdoc IWalletScore
    function getScoreSetMeta(ScoreSetId id) external view override returns (ScoreSetMeta memory) {
        if (ScoreSetId.unwrap(id) == 0 || _scoreSetMeta[id].scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }
        return _scoreSetMeta[id];
    }

    /// @inheritdoc IWalletScore
    function getRankAndScore(ScoreSetId id, address wallet) external view override returns (uint256 rank, uint256 score) {
        if (ScoreSetId.unwrap(id) == 0 || _scoreSetMeta[id].scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }
        rank = _scoreSetRanks[id][wallet];
        if (rank == 0) {
            return (0, 0);
        }
        score = _scoreSetEntries[id][rank - 1].score;
    }

    /// @inheritdoc IWalletScore
    function getRanksAndScores(ScoreSetId id, address[] calldata wallets)
        external
        view
        override
        returns (uint256[] memory ranks, uint256[] memory scores)
    {
        if (ScoreSetId.unwrap(id) == 0 || _scoreSetMeta[id].scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }

        ranks = new uint256[](wallets.length);
        scores = new uint256[](wallets.length);

        for (uint256 i = 0; i < wallets.length; i++) {
            uint256 rank = _scoreSetRanks[id][wallets[i]];
            ranks[i] = rank;
            scores[i] = rank > 0 ? _scoreSetEntries[id][rank - 1].score : 0;
        }
    }

    /// @inheritdoc IWalletScore
    function getEntryAtRank(ScoreSetId id, uint256 rank) external view override returns (Entry memory) {
        ScoreSetMeta storage meta = _scoreSetMeta[id];
        if (ScoreSetId.unwrap(id) == 0 || meta.scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }
        if (rank < meta.minRank || rank > meta.maxRank) {
            revert RankOutOfRange(rank, meta.minRank, meta.maxRank);
        }
        return _scoreSetEntries[id][rank - 1];
    }

    /// @inheritdoc IWalletScore
    function getEntriesInRankRange(ScoreSetId id, uint256 startRank, uint256 count)
        external
        view
        override
        returns (Entry[] memory)
    {
        ScoreSetMeta storage meta = _scoreSetMeta[id];
        if (ScoreSetId.unwrap(id) == 0 || meta.scoreTimestamp == 0) {
            revert ScoreSetNotFound(id);
        }

        // Clamp to valid range
        if (startRank < meta.minRank) {
            startRank = meta.minRank;
        }
        uint256 endRank = startRank + count - 1;
        if (endRank > meta.maxRank) {
            endRank = meta.maxRank;
        }
        if (startRank > endRank) {
            return new Entry[](0);
        }

        uint256 resultCount = endRank - startRank + 1;
        Entry[] memory result = new Entry[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = _scoreSetEntries[id][startRank - 1 + i];
        }
        return result;
    }

    /// @inheritdoc IWalletScore
    function getLatestScoreSetId(DomainId domainId, uint256 minTs, uint256 maxTs)
        external
        view
        override
        returns (ScoreSetId)
    {
        if (!_domainExists[domainId]) {
            revert DomainNotFound(domainId);
        }

        ScoreSetId[] storage scoreSets = _domainScoreSets[domainId];
        ScoreSetId latestId = ScoreSetId.wrap(0);
        uint256 latestTs = 0;

        // Iterate in reverse for efficiency (newer score sets are at the end)
        for (uint256 i = scoreSets.length; i > 0; i--) {
            ScoreSetId ssId = scoreSets[i - 1];
            ScoreSetMeta storage meta = _scoreSetMeta[ssId];

            if (meta.scoreTimestamp >= minTs && meta.scoreTimestamp <= maxTs) {
                if (meta.scoreTimestamp > latestTs) {
                    latestTs = meta.scoreTimestamp;
                    latestId = ssId;
                }
            }
        }

        return latestId;
    }

    /// @inheritdoc IWalletScore
    function getRequest(RequestId id) external view override returns (ScoreRequest memory) {
        if (_requests[id].requester == address(0)) {
            revert RequestNotFound(id);
        }
        return _requests[id];
    }

    /// @inheritdoc IWalletScore
    function getBid(BidId id) external view override returns (Bid memory) {
        if (RequestId.unwrap(_bids[id].requestId) == 0) {
            revert BidNotFound(id);
        }
        return _bids[id];
    }

    /// @inheritdoc IWalletScore
    function getRequestBids(RequestId id) external view override returns (BidId[] memory) {
        if (_requests[id].requester == address(0)) {
            revert RequestNotFound(id);
        }
        return _requestBids[id];
    }

    /// @inheritdoc IWalletScore
    function getTreasuryBalance() external view override returns (uint256) {
        return _treasuryBalance;
    }

    /// @inheritdoc IWalletScore
    function getMinPublisherBond() external view override returns (uint256) {
        return _minPublisherBond;
    }

    /// @inheritdoc IWalletScore
    function getDenylistParams()
        external
        view
        override
        returns (uint256 baseDuration, uint256 perLostBidder, uint256 valueDivisor)
    {
        return (_denylistBaseDuration, _denylistPerLostBidder, _denylistValueDivisor);
    }

    /// @inheritdoc IWalletScore
    function getWithdrawable(address addr) external view override returns (uint256) {
        return _withdrawable[addr];
    }

    /// @inheritdoc IWalletScore
    function withdraw() external override {
        uint256 amount = _withdrawable[msg.sender];
        if (amount == 0) return;

        _withdrawable[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed(msg.sender, amount);
        }
    }
}
