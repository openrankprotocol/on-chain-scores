// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {OnChainScores} from "../src/OnChainScores.sol";

contract ComputeManagerScript is Script {
    function run() public {
        // Load environment variables (such as private key, etc.)
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");

        // Start broadcasting the transaction
        vm.startBroadcast(deployerPrivateKey);

        OnChainScores onChainScores = new OnChainScores(owner);

        // Print the contract address
        console.log("OnChainScores contract deployed at:", address(onChainScores));

        vm.stopBroadcast();
    }
}
