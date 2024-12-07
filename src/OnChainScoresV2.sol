// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// TODO find a better name

/// @title Global Farcaster OpenkRank scores
/// @custom:oz-upgrades-from OnChainScoresV1
contract OnChainScoresV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /// @notice One leaderboard entry.
    struct User {
        /// @notice Farcaster ID of the user
        uint256 fid;
        /// @notice OpenRank score of the user.
        /// The value is scaled so that score range [0.0, 1.0) maps to
        /// [0, 2**256), e.g. 0x8000...0000 == 0.5, 0x4000...0000 == 0.25, etc.
        /// 1.0 is an exception: it maps not to 2**256 but to 2**256-1
        /// because 2**256 is out of uint256 range.
        /// Instead, type(uint256).max (2**256-1) unambiguously identifies 1.0.
        /// 1-2**-256, which is the score value that would otherwise map to
        /// the same type(uint256).max, cannot be represented,
        /// which is okay because it cannot be represented in IEEE 754 either.
        uint256 score;
    }

    /// @notice Leaderboard entries, sorted by score.
    User[] private leaderboard;

    /// @notice FID to their position (rank) in the leaderboard.
    /// @dev Invariant: an FID exists in fidRank iff it also appears in leaderboard.
    /// Rank values stored here are 1-based; 0 means fid not found.
    mapping(uint256 => uint256) public fidRank;

    /// @notice Emitted when a leaderboard entry has been set (added).
    /// @param fid Farcaster ID.
    /// @param rank Rank (position) in the leaderboard.
    /// @param score The score value.
    event ScoreSet(uint256 indexed fid, uint256 rank, uint256 score);

    /// @notice Emitted when a leaderboard entry has been deleted.
    /// @param fid Farcaster ID.
    /// @param rank Rank (position) in the leaderboard.
    /// @param score The score value.
    event ScoreDeleted(uint256 indexed fid, uint256 rank, uint256 score);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // make it impossible to call initialize() on the impl
        _disableInitializers();
    }

    /// @notice Initializes the contract state (which goes in the proxy).
    /// @dev Only for the proxy to call exactly once at deploy time.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Extends the leaderboard with additional entries at the end.
    function appendScores(User[] calldata users) external onlyOwner {
        uint256 start = leaderboard.length;
        uint256 lastScore = start > 0 ? leaderboard[start - 1].score : type(uint256).max;
        for (uint256 i = 0; i < users.length; i++) {
            uint256 fid = users[i].fid;
            require(fidRank[fid] == 0, "FID already ranked");
            uint256 score = users[i].score;
            require(score <= lastScore, "score not sorted");
            leaderboard.push(users[i]);
            fidRank[users[i].fid] = start + i + 1;
            emit ScoreSet(users[i].fid, start + i, score);
            lastScore = score;
        }
    }

    /// @notice Truncates a tail of the given length of the leaderboard.
    /// If the leaderboard has less entries, truncate to empty.
    function truncate(uint256 count) external onlyOwner {
        uint256 length = leaderboard.length;
        for (; length > 0 && count > 0; count--) {
            User memory user = leaderboard[--length];
            leaderboard.pop();
            delete fidRank[user.fid];
            emit ScoreDeleted(user.fid, leaderboard.length, user.score);
        }
    }

    /// @notice Returns number of entries in the leaderboard.
    function leaderboardLength() external view returns (uint256) {
        return leaderboard.length;
    }

    /// @notice Returns user (FID and score) at the given rank.
    /// @param rank The rank.  One-based, i.e. 1 is the top user.
    function getUserAtRank(uint256 rank) external view returns (User memory user) {
        require(rank >= 1 && rank <= leaderboard.length, "rank out of range");
        user = leaderboard[rank - 1];
    }

    /// @notice Returns users (FIDs and scores) at the given ranks.
    /// @param ranks The ranks.  One-based, i.e. 1 is the top user.
    /// Nonexistent ranks result in empty user (fid = 0, score = 0).
    function getUsersAtRanks(uint256[] calldata ranks) external view returns (User[] memory users) {
        users = new User[](ranks.length);
        for (uint256 i = 0; i < ranks.length; i++) {
            uint256 rank = ranks[i];
            if (rank >= 1 && rank <= leaderboard.length) {
                users[i] = leaderboard[rank - 1];
            }
        }
    }

    /// @notice Returns users (FIDs and scores) in the given rank range.
    /// @param start The first rank to return.  One-based, i.e. 1 is the top user.
    /// @param count The number of users to return.
    /// If start/count is too large, only those that are in the leaderboard are returned,
    /// e.g. on a 100-user leaderboard (ranks 1-100), start=91, count=20 (ranks 91-110) returns only 10 users
    /// (ranks 91-100), and start=101, count=10 (ranks 101-110) returns no users.
    function getUsersInRankRange(uint256 start, uint256 count) external view returns (User[] memory users) {
        if (start < 1) {
            start = 1;
        }
        start--; // convert to zero-based
        if (start >= leaderboard.length) {
            start = leaderboard.length;
        }
        if (start + count > leaderboard.length) {
            count = leaderboard.length - start;
        }
        users = new User[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = leaderboard[start++];
        }
    }

    /// @notice Returns the rank and score of the given FID.
    /// @param fid Farcaster ID.
    /// @return rank (One-based) rank; 0 means unranked.
    /// @return score Score value; 0 if unranked.
    function getRankAndScoreForFID(uint256 fid) external view returns (uint256 rank, uint256 score) {
        rank = fidRank[fid];
        score = rank > 0 ? leaderboard[rank - 1].score : 0;
    }

    /// @notice Returns the ranks and scores of the given FIDs.
    /// @param fids Farcaster IDs.
    /// @return ranks (One-based) ranks, i.e. 1 is the top user.  0 means unranked.
    /// @return scores Scores; 0 if unranked.
    function getRanksAndScoresForFIDs(uint256[] calldata fids)
        external
        view
        returns (uint256[] memory ranks, uint256[] memory scores)
    {
        ranks = new uint256[](fids.length);
        scores = new uint256[](fids.length);
        for (uint256 i = 0; i < fids.length; i++) {
            uint256 fid = fids[i];
            uint256 rank = fidRank[fid];
            ranks[i] = rank;
            scores[i] = rank > 0 ? leaderboard[rank - 1].score : 0;
        }
    }

    /// @notice Health check.  Used to check for installation.
    function healthCheck(uint256 nonce) public pure returns (uint256) {
        return nonce * 40 + 2;
    }
}
