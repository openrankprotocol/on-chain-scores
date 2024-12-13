// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DevRankV1} from "src/DevRank.sol";
import {IDevRank} from "src/IDevRank.sol";

contract ComputeManagerScript is Script {
    IDevRank.User[] private users;

    function run() public {
        // Load environment variables (such as private key, etc.)
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address proxy = vm.envAddress("DEVRANK_PROXY_CONTRACT_ADDRESS");

        // Start broadcasting the transaction
        vm.startBroadcast(deployerPrivateKey);

        bool upgrade = proxy != 0x0000000000000000000000000000000000000000;

        if (!upgrade) {
            proxy = Upgrades.deployUUPSProxy("DevRank.sol:DevRankV1", abi.encodeCall(DevRankV1.initialize, ()));
            console.log("deployed proxy at:", proxy);
        } else {
            Upgrades.upgradeProxy(proxy, "DevRank.sol:DevRankV1", "");
            console.log("upgraded proxy at:", proxy);
        }

        vm.stopBroadcast();
    }
}
