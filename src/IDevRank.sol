// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDevRank {
    /// @notice One leaderboard entry.
    struct User {
        /// @notice GitHub username.
        string username;
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

    // Functions

    /// @notice Gets the given user's rank.
    /// @param username GitHub username.
    /// @return rank Rank (position) in the leaderboard.
    function userRank(string memory username) external view returns (uint256 rank);

    /// @notice Returns number of entries in the leaderboard.
    function leaderboardLength() external view returns (uint256);

    /// @notice Returns user (username and score) at the given rank.
    /// @param rank The rank.  One-based, i.e. 1 is the top user.
    function getUserAtRank(uint256 rank) external view returns (User memory user);

    /// @notice Returns users (usernames and scores) at the given ranks.
    /// @param ranks The ranks.  One-based, i.e. 1 is the top user.
    /// Nonexistent ranks result in empty user (username = "", score = 0).
    function getUsersAtRanks(uint256[] calldata ranks) external view returns (User[] memory users);

    /// @notice Returns users (usernames and scores) in the given rank range.
    /// @param start The first rank to return.  One-based, i.e. 1 is the top user.
    /// @param count The number of users to return.
    /// If start/count is too large, only those that are in the leaderboard are returned,
    /// e.g. on a 100-user leaderboard (ranks 1-100), start=91, count=20 (ranks 91-110) returns only 10 users
    /// (ranks 91-100), and start=101, count=10 (ranks 101-110) returns no users.
    function getUsersInRankRange(uint256 start, uint256 count) external view returns (User[] memory users);

    /// @notice Returns the rank and score of the given user.
    /// @param username GitHub username.
    /// @return rank (One-based) rank; 0 means unranked.
    /// @return score Score value; 0 if unranked.
    function getRankAndScoreForUser(string memory username) external view returns (uint256 rank, uint256 score);

    /// @notice Returns the ranks and scores of the given usernames.
    /// @param usernames GitHub usernames.
    /// @return ranks (One-based) ranks, i.e. 1 is the top user.  0 means unranked.
    /// @return scores Scores; 0 if unranked.
    function getRanksAndScoresForUsers(string[] calldata usernames)
        external
        view
        returns (uint256[] memory ranks, uint256[] memory scores);
}
