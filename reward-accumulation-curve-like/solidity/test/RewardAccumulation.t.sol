// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RewardAccumulation} from "../src/RewardAccumulation.sol";
import {RewardAccumulationScript} from "../script/RewardAccumulation.s.sol";

contract RewardAccumulationTest is Test {
    RewardAccumulation public rewardAccumulation;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant WEEK = 604800;

    function setUp() public {
        RewardAccumulationScript rewardAccumulationScript = new RewardAccumulationScript();
        rewardAccumulation = rewardAccumulationScript.run();
    }

    function testContractDeploy() public view {
        assert(address(rewardAccumulation) != address(0));
    }

    function testRate() public view {
        uint256 rate = rewardAccumulation.getRate();
        assert(rate == 1e18);
    }

    function testWeight() public view {
        uint256 weight = rewardAccumulation.getWeight();
        assert(weight == 5e17);
    }

    function testUpdateWorkingBalanceMax() public {
        uint256 USER_LP_BALANCE = 10e18;
        uint256 TOTAL_LP_BALANCE = 100e18;
        uint256 USER_BOOST_BALANCE = 10e18;
        uint256 TOTAL_BOOST_BALANCE = 100e18;

        vm.prank(alice);
        rewardAccumulation.updateWorkingBalance(
            alice,
            USER_LP_BALANCE,
            TOTAL_LP_BALANCE,
            USER_BOOST_BALANCE,
            TOTAL_BOOST_BALANCE
        );

        uint256 user_wb = rewardAccumulation.getUserWb(alice);
        assert(user_wb == USER_LP_BALANCE);

        uint256 working_supply = rewardAccumulation.getWorkingSupply();
        assert(working_supply == USER_LP_BALANCE);
    }

    function testUpdateWorkingBalanceMin() public {
        uint256 USER_LP_BALANCE = 10e18;
        uint256 TOTAL_LP_BALANCE = 100e18;
        uint256 USER_BOOST_BALANCE = 0;
        uint256 TOTAL_BOOST_BALANCE = 100e18;

        vm.prank(alice);
        rewardAccumulation.updateWorkingBalance(
            alice,
            USER_LP_BALANCE,
            TOTAL_LP_BALANCE,
            USER_BOOST_BALANCE,
            TOTAL_BOOST_BALANCE
        );

        uint256 user_wb = rewardAccumulation.getUserWb(alice);
        assert(user_wb == (USER_LP_BALANCE * 40) / 100);

        uint256 working_supply = rewardAccumulation.getWorkingSupply();
        assert(working_supply == (USER_LP_BALANCE * 40) / 100);
    }

    function testCheckpoint() public {
        investLpTokenMaxBoostAlice();
        uint256 aliceR1 = rewardAccumulation.getUserReward(alice);
        assert(aliceR1 == 0);
        rewardAccumulation.checkpoint(alice);
        uint256 aliceR2 = rewardAccumulation.getUserReward(alice);
        assert(aliceR2 == 0);

        vm.warp(block.timestamp + WEEK);

        rewardAccumulation.checkpoint(alice);
        // rate * weight * dt * _working_balance // working_supply    1e18 * 5e17 * 604800 * 10e18 // 10e18 * 1e18 = 302400000000000000000000
        uint256 aliceR3 = rewardAccumulation.getUserReward(alice);
        assert(aliceR3 > 0);
        assert(aliceR3 == 302400000000000000000000);

        rewardAccumulation.checkpoint(bob);
        investLpTokenMaxBoostBob();

        vm.warp(block.timestamp + 2 * WEEK);

        // 30240000000000000000000 + rate * weight * dt * _working_balance // working_supply   30240000000000000000000 + 1e18 * 5e17 * 604800 * 10e18 // 20e18 * 1e18 = 30240000000000000000000 + 15120000000000000000000
        // 1st iter: 302400000000000000000000 + 10e18 * 15120000000000000000000 = 453600000000000000000000
        // 2st iter: 453600000000000000000000 + 10e18 * 15120000000000000000000 = 604800000000000000000000

        rewardAccumulation.checkpoint(alice);

        // rate * weight * dt * _working_balance // working_supply   1e18 * 5e17 * 604800 * 10e18 // 20e18 * 1e18 = 15120000000000000000000
        // 1st iter: 10e18 * 15120000000000000000000 = 151200000000000000000000
        // 2st iter: 151200000000000000000000 + 10e18 * 15120000000000000000000 = 302400000000000000000000
        rewardAccumulation.checkpoint(bob);

        uint256 aliceR4 = rewardAccumulation.getUserReward(alice);
        console.log(aliceR4);
        assert(aliceR4 == 604800000000000000000000);

        uint256 bobR1 = rewardAccumulation.getUserReward(bob);
        console.log(bobR1);
        assert(bobR1 == 302400000000000000000000);
    }

    // ------------------------------------------------------------------
    //                      UTIL FUNCTIONS
    // ------------------------------------------------------------------

    function investLpTokenMaxBoostAlice() internal {
        uint256 USER_LP_BALANCE = 10e18;
        uint256 TOTAL_LP_BALANCE = 100e18;
        uint256 USER_BOOST_BALANCE = 10e18;
        uint256 TOTAL_BOOST_BALANCE = 100e18;

        vm.prank(alice);
        rewardAccumulation.updateWorkingBalance(
            alice,
            USER_LP_BALANCE,
            TOTAL_LP_BALANCE,
            USER_BOOST_BALANCE,
            TOTAL_BOOST_BALANCE
        );
    }

    function investLpTokenMaxBoostBob() internal {
        uint256 USER_LP_BALANCE = 10e18;
        uint256 TOTAL_LP_BALANCE = 100e18;
        uint256 USER_BOOST_BALANCE = 10e18;
        uint256 TOTAL_BOOST_BALANCE = 100e18;

        vm.prank(bob);
        rewardAccumulation.updateWorkingBalance(
            bob,
            USER_LP_BALANCE,
            TOTAL_LP_BALANCE,
            USER_BOOST_BALANCE,
            TOTAL_BOOST_BALANCE
        );
    }
}
