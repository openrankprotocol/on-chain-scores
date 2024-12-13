// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OnChainScoresV2} from "src/OnChainScoresV2.sol";
import {IFarcasterOpenRank} from "src/IFarcasterOpenRank.sol";
import {IVerificationsV4Reader} from "src/IVerificationsV4Reader.sol";

contract ComputeManagerScript is Script {
    IFarcasterOpenRank.User[] private users;

    function run() public {
        // Load environment variables (such as private key, etc.)
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address proxy = vm.envAddress("FARCASTER_PROXY_CONTRACT_ADDRESS");
        address fidLookupAddress = vm.envAddress("FID_LOOKUP_ADDRESS");

        // Start broadcasting the transaction
        vm.startBroadcast(deployerPrivateKey);

        bool upgrade = proxy != 0x0000000000000000000000000000000000000000;

        if (!upgrade) {
            proxy = Upgrades.deployUUPSProxy("OnChainScoresV2.sol", abi.encodeCall(OnChainScoresV2.initialize, ()));
            console.log("deployed proxy at:", proxy);
        } else {
            Upgrades.upgradeProxy(proxy, "OnChainScoresV2.sol", "");
            console.log("upgraded proxy at:", proxy);
        }

        OnChainScoresV2 instance = OnChainScoresV2(proxy);
        instance.setFidLookup(IVerificationsV4Reader(fidLookupAddress));

        if (!upgrade) {
            require(instance.healthCheck(1) == 42, "deployment health check failed");

            users.push(IFarcasterOpenRank.User(2148, 100));
            users.push(IFarcasterOpenRank.User(2147, 10));
            instance.appendScores(users);

            require(instance.leaderboardLength() == 2);

            IFarcasterOpenRank.User memory user = instance.getUserAtRank(1);
            require(user.fid == 2148, "fid 2148 mismatch");
            require(user.score == 100, "score mismatch for fid 2148");

            user = instance.getUserAtRank(2);

            require(user.fid == 2147, "fid 2147 mismatch");
            require(user.score == 10, "score mismatch for fid 2147");

            instance.truncate(5);

            require(instance.leaderboardLength() == 0);
        }

        vm.stopBroadcast();
    }
}
