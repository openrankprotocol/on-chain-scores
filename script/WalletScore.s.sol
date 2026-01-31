// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {WalletScoreV1} from "src/WalletScore/WalletScoreV1.sol";

contract WalletScoreScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address proxy = vm.envOr("WALLETSCORE_PROXY_CONTRACT_ADDRESS", address(0));

        vm.startBroadcast(deployerPrivateKey);

        bool upgrade = proxy != address(0);

        if (!upgrade) {
            proxy = Upgrades.deployUUPSProxy(
                "WalletScore/WalletScoreV1.sol:WalletScoreV1", abi.encodeCall(WalletScoreV1.initialize, ())
            );
            console.log("deployed WalletScore proxy at:", proxy);
        } else {
            Upgrades.upgradeProxy(proxy, "WalletScore/WalletScoreV1.sol:WalletScoreV1", "");
            console.log("upgraded WalletScore proxy at:", proxy);
        }

        vm.stopBroadcast();
    }
}
