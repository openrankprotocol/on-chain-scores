// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract OnChainScores {
    // Owner address
    address public owner;
    mapping(uint256 => uint256) public fidToScores;
    mapping(uint256 => uint256) public fidToRank;
    event RankAmountSet(uint256 indexed fid, uint256 rank, uint256 score);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Initialize the contract with whitelisted addresses
    constructor(address _owner) {
        owner = _owner;
    }

    function setAirdropAmounts(
        uint256[] calldata fids,
        uint256[] calldata ranks,
        uint256[] calldata scores
    ) external onlyOwner {
        require(fids.length == scores.length, "Array lengths must match");
        require(ranks.length == scores.length, "Array lengths must match");

        for (uint256 i = 0; i < fids.length; i++) {
            fidToScores[fids[i]] = scores[i];
            fidToScores[fids[i]] = ranks[i];
            emit RankAmountSet(fids[i], ranks[i], scores[i]);
        }
    }
}
