// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

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
    Bid
} from "./Types.sol";

/// @title IWalletScore
/// @notice Interface for the WalletScore multi-domain wallet score registry.
interface IWalletScore {
    // ============ Events ============

    // Domain events
    event DomainRegistered(DomainId indexed domainId, string metadataUri);
    event DomainMetadataUpdated(DomainId indexed domainId, string metadataUri);

    // Publisher events
    event PublisherRegistered(PublisherId indexed publisherId, address indexed addr, string metadataUri);
    event PublisherAddressUpdated(PublisherId indexed publisherId, address indexed oldAddr, address indexed newAddr);
    event PublisherMetadataUpdated(PublisherId indexed publisherId, string metadataUri);
    event PublisherDeactivated(PublisherId indexed publisherId);
    event PublisherDenylisted(PublisherId indexed publisherId, uint256 until);

    // Score set events
    event ScoreSetCreated(ScoreSetId indexed scoreSetId, DomainId indexed domainId, PublisherId indexed publisher);
    event ScoreSetPublished(ScoreSetId indexed scoreSetId, uint256 entryCount, uint256 minRank, uint256 maxRank);

    // Bidding events
    event RequestCreated(
        RequestId indexed requestId, address indexed requester, DomainId indexed domainId, uint256 maxBudget
    );
    event BidSubmitted(
        BidId indexed bidId, RequestId indexed requestId, PublisherId indexed publisher, uint256 price, uint256 promisedDuration
    );
    event BidSelected(RequestId indexed requestId, BidId indexed bidId, PublisherId indexed publisher);
    event RequestFulfilled(
        RequestId indexed requestId, ScoreSetId indexed scoreSetId, PublisherId indexed publisher, uint256 payout
    );
    event BidderFailed(
        RequestId indexed requestId, BidId indexed bidId, PublisherId indexed publisher, uint256 slashAmount, uint256 denylistUntil
    );
    event RequestFailed(RequestId indexed requestId);
    event RequestCancelled(RequestId indexed requestId);

    // Bond events
    event BondDeposited(PublisherId indexed publisher, uint256 amount, uint256 newBalance);
    event BondWithdrawn(PublisherId indexed publisher, uint256 amount, uint256 newBalance);
    event SlashDistributed(
        RequestId indexed requestId, uint256 toTreasury, uint256 toLostBidders, uint256 toNextOrRequester
    );

    // ============ Errors ============

    // Domain errors
    error DomainAlreadyExists(DomainId domainId);
    error DomainNotFound(DomainId domainId);

    // Publisher errors
    error PublisherNotFound(PublisherId publisherId);
    error PublisherNotActive(PublisherId publisherId);
    error PublisherAddressAlreadyRegistered(address addr);
    error NotPublisherOrAdmin(PublisherId publisherId);
    error PublisherIsDenylisted(PublisherId publisherId, uint256 until);

    // Score set errors
    error ScoreSetNotFound(ScoreSetId scoreSetId);
    error ScoreSetNotDraft(ScoreSetId scoreSetId);
    error ScoreSetNotPublished(ScoreSetId scoreSetId);
    error NotScoreSetOwner(ScoreSetId scoreSetId);
    error InvalidRankRange(uint256 startRank, uint256 count);
    error RankOutOfRange(uint256 rank, uint256 min, uint256 max);
    error WalletNotInScoreSet(address wallet);

    // Request errors
    error RequestNotFound(RequestId requestId);
    error InvalidRequestParams();
    error InvalidDeadlines(uint256 quotingDeadline, uint256 fulfillmentDeadline);
    error NotRequester(RequestId requestId);
    error RequestNotCancellable(RequestId requestId, RequestStatus status);
    error RequestNotInQuotingPhase(RequestId requestId, RequestStatus status);
    error RequestNotAssigned(RequestId requestId, RequestStatus status);

    // Bid errors
    error BidNotFound(BidId bidId);
    error InsufficientBond(PublisherId publisherId, uint256 required, uint256 actual);
    error PriceExceedsBudget(uint256 price, uint256 maxBudget);
    error PromisedDurationExceedsDeadline(uint256 promisedDuration, uint256 availableTime);
    error NotCurrentBidder(RequestId requestId, PublisherId actual, PublisherId expected);
    error FulfillmentDeadlineExceeded(RequestId requestId, uint256 deadline, uint256 currentTime);
    error ScoreSetDoesNotCoverRequest(ScoreSetId scoreSetId, RequestId requestId);

    // Bond errors
    error InsufficientBondBalance(uint256 requested, uint256 available);
    error CannotWithdrawWithActiveBids(PublisherId publisherId);
    error BondBelowMinimum(uint256 remaining, uint256 minimum);

    // Treasury errors
    error InsufficientTreasuryBalance(uint256 requested, uint256 available);
    error TransferFailed(address to, uint256 amount);

    // ============ Admin Functions ============

    /// @notice Registers a new domain.
    function registerDomain(DomainId domainId, string calldata metadataUri) external;

    /// @notice Updates domain metadata.
    function updateDomainMetadata(DomainId domainId, string calldata metadataUri) external;

    /// @notice Registers a new publisher.
    function registerPublisher(address addr, string calldata metadataUri) external returns (PublisherId);

    /// @notice Updates a publisher's address. Requires current address owner or admin.
    function updatePublisherAddress(PublisherId id, address newAddr) external;

    /// @notice Updates a publisher's metadata. Requires publisher or admin.
    function updatePublisherMetadata(PublisherId id, string calldata metadataUri) external;

    /// @notice Deactivates a publisher. Admin only.
    function deactivatePublisher(PublisherId id) external;

    /// @notice Sets minimum bond requirement for publishers.
    function setMinPublisherBond(uint256 amount) external;

    /// @notice Sets denylist calculation parameters.
    function setDenylistParams(uint256 baseDuration, uint256 perLostBidder, uint256 valueDivisor) external;

    /// @notice Withdraws from treasury. Admin only.
    function withdrawTreasury(address to, uint256 amount) external;

    // ============ Publisher Bond Functions ============

    /// @notice Deposits bond for the caller's publisher ID.
    function depositBond() external payable;

    /// @notice Withdraws bond. Requires no active bids and maintains minBond.
    function withdrawBond(uint256 amount) external;

    /// @notice Gets a publisher's bond balance.
    function getPublisherBond(PublisherId id) external view returns (uint256);

    // ============ Publisher Score Set Functions ============

    /// @notice Creates a new score set in Draft status.
    function createScoreSet(DomainId domainId, uint256 scoreTimestamp) external returns (ScoreSetId);

    /// @notice Adds scores to a draft score set.
    function addScoresToScoreSet(ScoreSetId id, uint256 startRank, Entry[] calldata entries) external;

    /// @notice Publishes (finalizes) a score set.
    function publishScoreSet(ScoreSetId id) external;

    // ============ Requester Functions ============

    /// @notice Creates a score request with deposit.
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
    ) external payable returns (RequestId);

    /// @notice Cancels a request. Only before assignment, refunds deposit.
    function cancelRequest(RequestId id) external;

    // ============ Publisher Bidding Functions ============

    /// @notice Submits a bid for a request.
    function submitBid(RequestId requestId, uint256 price, uint256 promisedDuration) external returns (BidId);

    // ============ Settlement Functions ============

    /// @notice Advances request state machine. Anyone can call, idempotent.
    function advanceRequest(RequestId id) external;

    /// @notice Publisher fulfills their assigned bid.
    function fulfillRequest(RequestId id, ScoreSetId scoreSetId) external;

    // ============ Query Functions ============

    /// @notice Gets domain metadata URI.
    function getDomainMetadataUri(DomainId id) external view returns (string memory);

    /// @notice Gets publisher by ID.
    function getPublisher(PublisherId id) external view returns (Publisher memory);

    /// @notice Gets publisher ID and data by address.
    function getPublisherByAddress(address addr) external view returns (PublisherId, Publisher memory);

    /// @notice Gets score set metadata.
    function getScoreSetMeta(ScoreSetId id) external view returns (ScoreSetMeta memory);

    /// @notice Gets rank and score for a wallet in a score set.
    function getRankAndScore(ScoreSetId id, address wallet) external view returns (uint256 rank, uint256 score);

    /// @notice Gets ranks and scores for multiple wallets.
    function getRanksAndScores(ScoreSetId id, address[] calldata wallets)
        external
        view
        returns (uint256[] memory ranks, uint256[] memory scores);

    /// @notice Gets entry at a specific rank.
    function getEntryAtRank(ScoreSetId id, uint256 rank) external view returns (Entry memory);

    /// @notice Gets entries in a rank range.
    function getEntriesInRankRange(ScoreSetId id, uint256 startRank, uint256 count)
        external
        view
        returns (Entry[] memory);

    /// @notice Finds latest score set for a domain within timestamp window.
    function getLatestScoreSetId(DomainId domainId, uint256 minTs, uint256 maxTs) external view returns (ScoreSetId);

    /// @notice Gets request by ID.
    function getRequest(RequestId id) external view returns (ScoreRequest memory);

    /// @notice Gets bid by ID.
    function getBid(BidId id) external view returns (Bid memory);

    /// @notice Gets all bids for a request.
    function getRequestBids(RequestId id) external view returns (BidId[] memory);

    /// @notice Gets treasury balance.
    function getTreasuryBalance() external view returns (uint256);

    /// @notice Gets minimum publisher bond requirement.
    function getMinPublisherBond() external view returns (uint256);

    /// @notice Gets denylist parameters.
    function getDenylistParams()
        external
        view
        returns (uint256 baseDuration, uint256 perLostBidder, uint256 valueDivisor);

    /// @notice Gets withdrawable balance for an address (refunds, slash distributions).
    function getWithdrawable(address addr) external view returns (uint256);

    /// @notice Withdraws any withdrawable balance for the caller.
    function withdraw() external;
}
