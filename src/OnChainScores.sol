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

    /// @notice Sets/replaces the leaderboard entry at ranks[i] with users[i].
    function setScores(uint256[] calldata ranks, User[] calldata users) external onlyOwner {
        require(ranks.length == users.length, "Array lengths must match");

        for (uint256 i = 0; i < ranks.length; i++) {
            require(ranks[i] < leaderboard.length, "Index exceeded the size of array");

            leaderboard[ranks[i]] = users[i];
            fidRank[ranks[i]] = ranks[i];
            emit ScoreSet(users[i].fid, ranks[i], users[i].score);
        }
    }

    /// @notice Extends the leaderboard with additional entries at the end.
    function appendScores(User[] calldata users) external onlyOwner {
        uint256 start = leaderboard.length;
        for (uint256 i = 0; i < users.length; i++) {
            leaderboard.push(users[i]);
            fidRank[users[i].fid] = start + i;
            emit ScoreSet(users[i].fid, start + i, users[i].score);
        }
    }

    /// @notice Wipes leaderboard entries at the given ranks.
    /// The entries are zeroed out (FID 0, score 0).
    function deleteScores(uint256[] calldata ranks) external onlyOwner {
        for (uint256 i = 0; i < ranks.length; i++) {
            require(ranks[i] < leaderboard.length, "Index exceeded the size of array");
            uint256 rank = ranks[i];
            if (leaderboard[rank].fid != 0) {
                emit ScoreDeleted(leaderboard[rank].fid, rank, leaderboard[rank].score);
            }
            delete leaderboard[rank];
            delete fidRank[i];
        }
    }

    /// @notice Purges the entire leaderboard.
    /// Upon success, the leaderboard has no entries (zero length).
    function purgeLeaderboard() external onlyOwner {
        for (uint256 rank = 0; rank < leaderboard.length; rank++) {
            if (leaderboard[rank].fid != 0) {
                emit ScoreDeleted(leaderboard[rank].fid, rank, leaderboard[rank].score);
            }
            delete fidRank[leaderboard[rank].fid];
        }
        delete leaderboard;
    }

    /// @notice Health check.  Used to check for installation.
    function healthCheck(uint256 nonce) public pure returns (uint256) {
        return nonce * 40 + 2;
    }
}
