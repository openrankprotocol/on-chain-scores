// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// TODO find a better name

/// @title Global Farcaster OpenkRank scores
contract OnChainScores is Initializable, UUPSUpgradeable, OwnableUpgradeable {
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
    User[] public leaderboard;

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

    // TODO document the event behavior upon score update

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

    /// @notice Truncate a tail of the given length of the leaderboard.
    /// If the leaderboard has less entries, truncate to empty.
    function truncate(uint256 count) external onlyOwner {
        uint256 length = leaderboard.length;
        for(; length > 0 && count > 0; count--) {
            User memory user = leaderboard[--length];
            leaderboard.pop();
            delete fidRank[user.fid];
            emit ScoreDeleted(user.fid, leaderboard.length, user.score);
        }
    }

    /// @notice Return number of entries in the leaderboard.
    function leaderboardLength() external view returns (uint256) {
        return leaderboard.length;
    }

    /// @notice Health check.  Used to check for installation.
    function healthCheck(uint256 nonce) public pure returns (uint256) {
        return nonce * 40 + 2;
    }
}
