// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DepositDecay} from "../src/DepositDecay.sol";
import {DepositDecayScript} from "../script/DepositDecay.s.sol";

contract DepositDecayTest is Test {
    DepositDecay public depositDecay;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant WEEK = 604800;
    uint256 constant YEAR = 365 * 86400;

    function setUp() public {
        DepositDecayScript depositDecayScript = new DepositDecayScript();
        depositDecay = depositDecayScript.run();
    }

    function testContractDeploy() public view {
        assert(address(depositDecay) != address(0));
    }

    function testCheckpoint() public {
        uint256 AMOUNT = 100e18;
        uint256 END = block.timestamp + 4 * YEAR;

        // Alice first deposit
        depositDecay.checkpoint(
            alice,
            DepositDecay.LockedBalance(0, 0),
            DepositDecay.LockedBalance(int128(int256(AMOUNT)), END)
        );
        uint256 alice_bal = depositDecay.balanceOf(alice);
        assertApproxEqRel(alice_bal, (AMOUNT * 99) / 100, (1e18 * 1) / 100); // truncation loses 1% of deposited amount
        assertApproxEqRel(alice_bal, (AMOUNT * 99) / 100, (1e18 * 1) / 100); // truncation loses 1% of deposited amount

        // Bob first deposit
        depositDecay.checkpoint(
            bob,
            DepositDecay.LockedBalance(0, 0),
            DepositDecay.LockedBalance(int128(int256(AMOUNT)), END)
        );
        uint256 bob_bal = depositDecay.balanceOf(bob);
        assertApproxEqRel(bob_bal, (AMOUNT * 99) / 100, (1e18 * 1) / 100); // truncation loses 1% of deposited amount
        assertApproxEqRel(bob_bal, (AMOUNT * 99) / 100, (1e18 * 1) / 100); // truncation loses 1% of deposited amount

        uint256 supply = depositDecay.totalSupply();
        assert(supply == bob_bal + alice_bal);

        vm.warp(block.timestamp + 2 * YEAR);

        uint256 alice_bal2 = depositDecay.balanceOf(alice);
        assertApproxEqRel(alice_bal2, alice_bal / 2, (1e18 * 1) / 100); // truncation loses 1% of deposited amount

        uint256 bob_bal2 = depositDecay.balanceOf(bob);
        assertApproxEqRel(bob_bal2, bob_bal / 2, (1e18 * 1) / 100); // truncation loses 1% of deposited amount

        uint256 supply2 = depositDecay.totalSupply();
        assertApproxEqRel(supply2, supply / 2, (1e18 * 1) / 100);

        uint256 AMOUNT2 = 200e18; // double the amount
        uint256 END2 = block.timestamp + 2 * YEAR; // same end as before

        // Alice second deposit
        depositDecay.checkpoint(
            alice,
            DepositDecay.LockedBalance(int128(int256(AMOUNT)), END),
            DepositDecay.LockedBalance(int128(int256(AMOUNT2)), END2)
        );

        uint256 bob_bal3 = depositDecay.balanceOf(bob);
        assert(bob_bal2 == bob_bal3);
        uint256 alice_bal3 = depositDecay.balanceOf(alice); // doubles the balance
        assertApproxEqRel(alice_bal2 * 2, alice_bal3, (1e18 * 1) / 100);

        vm.warp(block.timestamp + YEAR); // 3 years passed

        uint256 bob_bal4 = depositDecay.balanceOf(bob);
        assertApproxEqRel(bob_bal4, bob_bal3 / 2, (1e18 * 1) / 100);

        uint256 alice_bal4 = depositDecay.balanceOf(alice);
        assertApproxEqRel(alice_bal4, alice_bal3 / 2, (1e18 * 1) / 100);

        uint256 supply3 = depositDecay.totalSupply();
        assertApproxEqRel(supply3, alice_bal4 + bob_bal4, (1e18 * 1) / 100);

        vm.warp(block.timestamp + YEAR); // 4 years passed

        uint256 bob_bal5 = depositDecay.balanceOf(bob);
        assert(bob_bal5 == 0);

        uint256 alice_bal5 = depositDecay.balanceOf(alice);
        assert(alice_bal5 == 0);

        uint256 supply4 = depositDecay.totalSupply();
        assert(supply4 == 0);
    }
}
