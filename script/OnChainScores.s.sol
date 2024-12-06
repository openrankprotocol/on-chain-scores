// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OnChainScores} from "../src/OnChainScores.sol";

contract ComputeManagerScript is Script {

OnChainScores.User[] private users;

    function run() public {
        // Load environment variables (such as private key, etc.)
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_CONTRACT_ADDRESS");

        // Start broadcasting the transaction
        vm.startBroadcast(deployerPrivateKey);

        if (proxy == 0x0000000000000000000000000000000000000000) {
            proxy = Upgrades.deployUUPSProxy("OnChainScores.sol", abi.encodeCall(OnChainScores.initialize, ()));
        } else {
            Upgrades.upgradeProxy(proxy, "OnChainScores.sol", "");
        }
        console.log("proxy deployed at:", proxy);

        OnChainScores instance = OnChainScores(proxy);
        require(instance.healthCheck(1) == 42, "deployment health check failed");

        users.push(OnChainScores.User(2148, 100));
        users.push(OnChainScores.User(2147, 10));
        instance.appendScores(users);

        uint256 fid;
        uint256 score;

        require(instance.leaderboardLength() == 2);

        (fid, score) = instance.leaderboard(0);
        require(fid == 2148, "fid 2148 mismatch");
        require(score == 100, "score mismatch for fid 2148");

        (fid, score) = instance.leaderboard(1);

        require(fid == 2147, "fid 2147 mismatch");
        require(score == 10, "score mismatch for fid 2147");

        instance.truncate(5);

        require(instance.leaderboardLength() == 0);

        vm.stopBroadcast();
    }
}
