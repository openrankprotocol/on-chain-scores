// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IFarcasterOpenRank} from "src/IFarcasterOpenRank.sol";

contract FarcasterOpenRankExample {
    IFarcasterOpenRank private farcasterOpenRank;

    constructor(address _farcasterOpenRank) {
        farcasterOpenRank = IFarcasterOpenRank(_farcasterOpenRank);
    }

    function isTop100(address verifier) external view returns (bool) {
        (, uint256 rank,) = farcasterOpenRank.getFIDRankAndScoreForVerifier(verifier);
        return rank >= 1 && rank <= 100;
    }
}
