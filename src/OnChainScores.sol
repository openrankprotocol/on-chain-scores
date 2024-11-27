// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract OnChainScores {
    // Owner address
    address public owner;
    mapping(uint256 => mapping(uint256 => uint256)) public fidToScores;
    event ScoreSet(uint256 indexed fid, uint256 score, uint256 mapVersion);

    mapping(uint256 => uint256[]) public ranks;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Initialize the contract with whitelisted addresses
    constructor(address _owner) {
        owner = _owner;
    }

    function setScores(
        uint256 mapVersion,
        uint256[] calldata fids,
        uint256[] calldata scores
    ) external onlyOwner {
        require(fids.length == scores.length, "Array lengths must match");

        for (uint256 i = 0; i < fids.length; i++) {
            fidToScores[mapVersion][fids[i]] = scores[i];
            emit ScoreSet(fids[i], scores[i], mapVersion);
        }
    }

    function setRanks(
        uint256 mapVersion,
        uint256[] calldata topN
    ) external onlyOwner {
        ranks[mapVersion] = topN;
    }
}
