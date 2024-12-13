// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IDevRank} from "src/IDevRank.sol";

/// @title DevRank scores
contract DevRankV1 is IDevRank, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // --- BEGIN state variables ---

    /// @notice Leaderboard entries, sorted by score.
    User[] private leaderboard;

    /// @dev Username to their position (rank) in the leaderboard.
    /// Invariant: a username exists in userRanks iff it also appears in leaderboard.
    /// Rank values stored here are 1-based; 0 means user not found.
    mapping(string => uint256) public userRank;

    // --- END state variables ---

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
            string memory username = users[i].username;
            require(bytes(username).length > 0, "empty username");
            require(userRank[username] == 0, "user already ranked");
            uint256 score = users[i].score;
            require(score <= lastScore, "score not sorted");
            leaderboard.push(users[i]);
            userRank[users[i].username] = start + i + 1;
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
            delete userRank[user.username];
        }
    }

    // --- BEGIN impl IDevRank ---

    function leaderboardLength() external view returns (uint256) {
        return leaderboard.length;
    }

    function getUserAtRank(uint256 rank) external view returns (User memory user) {
        require(rank >= 1 && rank <= leaderboard.length, "rank out of range");
        user = leaderboard[rank - 1];
    }

    function getUsersAtRanks(uint256[] calldata ranks) external view returns (User[] memory users) {
        users = new User[](ranks.length);
        for (uint256 i = 0; i < ranks.length; i++) {
            uint256 rank = ranks[i];
            if (rank >= 1 && rank <= leaderboard.length) {
                users[i] = leaderboard[rank - 1];
            }
        }
    }

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

    function getRankAndScoreForUser(string memory username) external view returns (uint256 rank, uint256 score) {
        (rank, score) = _getRankAndScoreForUser(username);
    }

    function _getRankAndScoreForUser(string memory username) private view returns (uint256 rank, uint256 score) {
        rank = bytes(username).length > 0 ? userRank[username] : 0;
        score = rank > 0 ? leaderboard[rank - 1].score : 0;
    }

    function getRanksAndScoresForUsers(string[] calldata usernames)
        external
        view
        returns (uint256[] memory ranks, uint256[] memory scores)
    {
        (ranks, scores) = _getRanksAndScoresForUsers(usernames);
    }

    function _getRanksAndScoresForUsers(string[] memory usernames)
        private
        view
        returns (uint256[] memory ranks, uint256[] memory scores)
    {
        ranks = new uint256[](usernames.length);
        scores = new uint256[](usernames.length);
        for (uint256 i = 0; i < usernames.length; i++) {
            string memory username = usernames[i];
            uint256 rank = bytes(username).length > 0 ? userRank[username] : 0;
            ranks[i] = rank;
            scores[i] = rank > 0 ? leaderboard[rank - 1].score : 0;
        }
    }

    // --- END impl IDevRank ---
}
