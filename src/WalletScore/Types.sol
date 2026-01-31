// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// ============ User-Defined Types ============

/// @dev Domain identifier, typically keccak256(name) or admin-assigned.
type DomainId is bytes32;

/// @dev Score set identifier, auto-incrementing starting from 1. 0 = not found.
type ScoreSetId is uint256;

/// @dev Request identifier, auto-incrementing starting from 1.
type RequestId is uint256;

/// @dev Publisher identifier, auto-incrementing starting from 1.
type PublisherId is uint256;

/// @dev Bid identifier, auto-incrementing starting from 1.
type BidId is uint256;

// ============ Enums ============

/// @dev Status of a score set.
enum ScoreSetStatus {
    Draft, // Being populated, not yet published
    Published // Finalized, no more edits allowed
}

/// @dev How the requester wants to select a winning bid.
enum BidSelection {
    Cheapest, // Lowest price wins
    Fastest // Shortest promisedDuration wins
}

/// @dev Status of a score request.
enum RequestStatus {
    Quoting, // Accepting bids (before quotingDeadline)
    Selecting, // Quoting closed, awaiting selectWinner() via advanceRequest()
    Assigned, // Winner selected, awaiting fulfillment
    Fulfilled, // Completed successfully
    Failed, // All bidders failed or deadline passed
    Cancelled // Requester cancelled (only before assignment)
}

/// @dev Status of a bid.
enum BidStatus {
    Pending, // Submitted, awaiting selection
    Selected, // Currently assigned to fulfill
    Won, // Successfully fulfilled
    Failed, // Failed to fulfill (slashed)
    Superseded // Another bidder selected after this one failed
}

// ============ Structs ============

/// @dev Publisher information.
struct Publisher {
    address currentAddress; // Can be migrated
    string metadataUri; // JSON: name, description, docs URL
    bool active; // Whether publisher can operate
    uint256 denylistUntil; // block.timestamp when bidding ban expires (0 = not banned)
}

/// @dev Score set metadata.
struct ScoreSetMeta {
    DomainId domainId; // Which domain this score set belongs to
    PublisherId publisher; // Who created this score set
    uint256 scoreTimestamp; // When scores were calculated
    uint256 minRank; // Lowest rank in set (1-based)
    uint256 maxRank; // Highest rank in set
    ScoreSetStatus status; // Draft or Published
    bytes32 merkleRoot; // Future: for verification
}

/// @dev A single score entry (wallet + score).
struct Entry {
    address wallet;
    uint256 score;
}

/// @dev A score request from a user.
struct ScoreRequest {
    address requester;
    DomainId domainId;
    address[] wallets; // Specific wallets (empty = use rank range)
    uint256 startRank; // If wallets empty, start rank (1-based)
    uint256 rankCount; // If wallets empty, number of ranks
    uint256 minScoreTimestamp; // Minimum acceptable score timestamp
    uint256 maxScoreTimestamp; // Maximum acceptable score timestamp
    uint256 quotingDeadline; // Bids must arrive by this time
    uint256 fulfillmentDeadline; // Must be fulfilled by this time
    uint256 maxBudget; // Deposited by requester
    BidSelection selectionMode;
    RequestStatus status;
    BidId currentBid; // Currently assigned bid (0 = none)
}

/// @dev A bid from a publisher.
struct Bid {
    RequestId requestId;
    PublisherId publisher;
    uint256 price; // Amount requested
    uint256 promisedDuration; // Seconds needed after selection
    uint256 submittedAt; // When bid was submitted
    uint256 selectedAt; // When this bid was selected (0 = not yet)
    BidStatus status;
}

/// @dev Internal struct for tracking lost bidders during slash distribution.
struct LostBidder {
    BidId bidId;
    uint256 quotedPrice;
}
