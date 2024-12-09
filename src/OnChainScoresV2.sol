// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IFarcasterOpenRank} from "./IFarcasterOpenRank.sol";
import {IVerificationsV4Reader} from "src/IVerificationsV4Reader.sol";

// TODO find a better name

/// @title Global Farcaster OpenkRank scores
/// @custom:oz-upgrades-from OnChainScoresV1
contract OnChainScoresV2 is IFarcasterOpenRank, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // --- BEGIN state variables ---

    /// @notice Leaderboard entries, sorted by score.
    User[] private leaderboard;

    /// @notice FID to their position (rank) in the leaderboard.
    /// @dev Invariant: an FID exists in fidRank iff it also appears in leaderboard.
    /// Rank values stored here are 1-based; 0 means fid not found.
    mapping(uint256 => uint256) public fidRank;

    /// @dev FID lookup contract
    IVerificationsV4Reader public fidLookup;

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

    function setFidLookup(IVerificationsV4Reader _fidLookup) public onlyOwner {
        fidLookup = _fidLookup;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Extends the leaderboard with additional entries at the end.
    function appendScores(User[] calldata users) external onlyOwner {
        uint256 start = leaderboard.length;
        uint256 lastScore = start > 0 ? leaderboard[start - 1].score : type(uint256).max;
        for (uint256 i = 0; i < users.length; i++) {
            uint256 fid = users[i].fid;
            require(fid != 0, "zero FID");
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

    // --- BEGIN impl IFarcasterOpenRank ---

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

    function getRankAndScoreForFID(uint256 fid) external view returns (uint256 rank, uint256 score) {
        (rank, score) = _getRankAndScoreForFID(fid);
    }

    function _getRankAndScoreForFID(uint256 fid) private view returns (uint256 rank, uint256 score) {
        rank = fid > 0 ? fidRank[fid] : 0;
        score = rank > 0 ? leaderboard[rank - 1].score : 0;
    }

    function getRanksAndScoresForFIDs(uint256[] calldata fids)
        external
        view
        returns (uint256[] memory ranks, uint256[] memory scores)
    {
        (ranks, scores) = _getRanksAndScoresForFIDs(fids);
    }

    function _getRanksAndScoresForFIDs(uint256[] memory fids)
        private
        view
        returns (uint256[] memory ranks, uint256[] memory scores)
    {
        ranks = new uint256[](fids.length);
        scores = new uint256[](fids.length);
        for (uint256 i = 0; i < fids.length; i++) {
            uint256 fid = fids[i];
            uint256 rank = fid > 0 ? fidRank[fid] : 0;
            ranks[i] = rank;
            scores[i] = rank > 0 ? leaderboard[rank - 1].score : 0;
        }
    }

    function getFIDRankAndScoreForVerifier(address verifier)
        external
        view
        returns (uint256 fid, uint256 rank, uint256 score)
    {
        fid = fidLookup.getFid(verifier);
        (rank, score) = _getRankAndScoreForFID(fid);
    }

    function getFIDsRanksAndScoresForVerifiers(address[] calldata verifiers)
        external
        view
        returns (uint256[] memory fids, uint256[] memory ranks, uint256[] memory scores)
    {
        fids = fidLookup.getFids(verifiers);
        (ranks, scores) = _getRanksAndScoresForFIDs(fids);
    }

    // --- END impl IFarcasterOpenRank ---

    /// @notice Health check.  Used to check for installation.
    function healthCheck(uint256 nonce) public pure returns (uint256) {
        return nonce * 40 + 2;
    }
}
