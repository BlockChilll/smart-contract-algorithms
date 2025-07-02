// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DepositDecay} from "../src/DepositDecay.sol";
import {Script, console} from "forge-std/Script.sol";

contract DepositDecayScript is Script {
    DepositDecay public depositDecay;

    function run() public returns (DepositDecay) {
        vm.startBroadcast();

        // rate is 1, weight is 0.5
        depositDecay = new DepositDecay();

        vm.stopBroadcast();

        return depositDecay;
    }
}
