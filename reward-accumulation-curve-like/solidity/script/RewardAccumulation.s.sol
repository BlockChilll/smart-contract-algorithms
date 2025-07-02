// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RewardAccumulation} from "../src/RewardAccumulation.sol";
import {Script, console} from "forge-std/Script.sol";

contract RewardAccumulationScript is Script {
    RewardAccumulation public rewardAccumulation;

    function run() public returns (RewardAccumulation) {
        vm.startBroadcast();

        // rate is 1, weight is 0.5
        rewardAccumulation = new RewardAccumulation(1e18, 5e17);

        vm.stopBroadcast();

        return rewardAccumulation;
    }
}
