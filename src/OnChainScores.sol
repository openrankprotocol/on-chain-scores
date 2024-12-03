// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract OnChainScores {
    // Owner address
    address public owner;

    struct User {
        uint256 fid;
        uint256 score;
    }

    User[] public leaderboard;

    event ScoreSet(uint256 indexed fid, uint256 rank, uint256 score);
    event ScoreDeleted(uint256 indexed fid, uint256 rank, uint256 score);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Initialize the contract with whitelisted addresses
    constructor(address _owner) {
        owner = _owner;
    }

    function setScores(uint256[] calldata ranks, User[] calldata users) external onlyOwner {
        require(ranks.length == users.length, "Array lengths must match");

        for (uint256 i = 0; i < ranks.length; i++) {
            require(ranks[i] < leaderboard.length, "Index exceeded the size of array");

            leaderboard[ranks[i]] = users[i];
            emit ScoreSet(users[i].fid, ranks[i], users[i].score);
        }
    }

    function appendScores(User[] calldata users) external onlyOwner {
        uint256 start = leaderboard.length;
        for (uint256 i = 0; i < users.length; i++) {
            leaderboard.push(users[i]);
            emit ScoreSet(users[i].fid, start + i, users[i].score);
        }
    }

    function deleteScores(uint256[] calldata ranks) external onlyOwner {
        for (uint256 i = 0; i < ranks.length; i++) {
            require(ranks[i] < leaderboard.length, "Index exceeded the size of array");

            delete leaderboard[ranks[i]];
            emit ScoreSet(leaderboard[ranks[i]].fid, ranks[i], leaderboard[ranks[i]].score);
        }
    }
}
