// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IFarcasterOpenRank {
    /// @notice One leaderboard entry.
    struct User {
        /// @notice Farcaster ID of the user
        uint256 fid; // Farcaster ID of the user
        /// @notice OpenRank score of the user.
        /// The value is scaled so that score range [0.0, 1.0) maps to
        /// [0, 2**256), e.g. 0x8000...0000 == 0.5, 0x4000...0000 == 0.25, etc.
        /// 1.0 is an exception: it maps not to 2**256 but to 2**256-1
        /// because 2**256 is out of uint256 range.
        /// Instead, type(uint256).max (2**256-1) unambiguously identifies 1.0.
        /// 1-2**-256, which is the score value that would otherwise map to
        /// the same type(uint256).max, cannot be represented,
        /// which is okay because it cannot be represented in IEEE 754 either.
        uint256 score; // OpenRank score of the user
    }

    // Events

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

    // Functions
    /// @notice Gets the given FID's rank.
    /// @param fid Farcaster ID.
    /// @return rank Rank (position) in the leaderboard.
    function fidRank(uint256 fid) external view returns (uint256 rank);

    /// @notice Returns number of entries in the leaderboard.
    function leaderboardLength() external view returns (uint256);

    /// @notice Returns user (FID and score) at the given rank.
    /// @param rank The rank.  One-based, i.e. 1 is the top user.
    function getUserAtRank(uint256 rank) external view returns (User memory user);

    /// @notice Returns users (FIDs and scores) at the given ranks.
    /// @param ranks The ranks.  One-based, i.e. 1 is the top user.
    /// Nonexistent ranks result in empty user (fid = 0, score = 0).
    function getUsersAtRanks(uint256[] calldata ranks) external view returns (User[] memory users);

    /// @notice Returns users (FIDs and scores) in the given rank range.
    /// @param start The first rank to return.  One-based, i.e. 1 is the top user.
    /// @param count The number of users to return.
    /// If start/count is too large, only those that are in the leaderboard are returned,
    /// e.g. on a 100-user leaderboard (ranks 1-100), start=91, count=20 (ranks 91-110) returns only 10 users
    /// (ranks 91-100), and start=101, count=10 (ranks 101-110) returns no users.
    function getUsersInRankRange(uint256 start, uint256 count) external view returns (User[] memory users);

    /// @notice Returns the rank and score of the given FID.
    /// @param fid Farcaster ID.
    /// @return rank (One-based) rank; 0 means unranked.
    /// @return score Score value; 0 if unranked.
    function getRankAndScoreForFID(uint256 fid) external view returns (uint256 rank, uint256 score);

    /// @notice Returns the ranks and scores of the given FIDs.
    /// @param fids Farcaster IDs.
    /// @return ranks (One-based) ranks, i.e. 1 is the top user.  0 means unranked.
    /// @return scores Scores; 0 if unranked.
    function getRanksAndScoresForFIDs(uint256[] calldata fids)
        external
        view
        returns (uint256[] memory ranks, uint256[] memory scores);

    /// @notice Returns the FID, rank, and score for the given verifier address.
    /// @param verifier Verifier address.
    /// @return fid Farcaster ID; 0 if no FID is associated with the given verifier address.
    /// @return rank (One-based) rank; 0 if unranked or no FID is associated with the given verifier address.
    /// @return score Score value; 0 if unranked or no FID is associated with the given verifier address.
    function getFIDRankAndScoreForVerifier(address verifier)
        external
        view
        returns (uint256 fid, uint256 rank, uint256 score);

    /// @notice Returns the FIDs, ranks, and scores for the given verifier addresses.
    /// @param verifiers Verifier addresses.
    /// @return fids Farcaster IDs; 0 if no FID is associated with the given verifier address.
    /// @return ranks (One-based) ranks; 0 if unranked or no FID is associated with the given verifier address.
    /// @return scores Score values; 0 if unranked or no FID is associated with the given verifier address.
    function getFIDsRanksAndScoresForVerifiers(address[] calldata verifiers)
        external
        view
        returns (uint256[] memory fids, uint256[] memory ranks, uint256[] memory scores);
}
