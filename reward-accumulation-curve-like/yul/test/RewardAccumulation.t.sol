// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IRewardAccumulation} from "./interfaces/IRewardAccumulation.sol";

contract RewardAccumulationTest is Test {
    IRewardAccumulation public rewardAccumulation;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant WEEK = 604800;

    uint256 s_rate = 1e18;
    uint256 s_weight = 5e17;

    function setUp() public {
        bytes
            memory bytecode = hex"600160055560055f5260205f20429055600160065560065f525f60208120556040610421806100475f396706f05b59d3b200008152670de0b6b3a76400006020820152015ff3fe3461012c575f3560e01c8063fe0aa1031461009d578063b10fb7aa14610098578063a972985e1461008d578063679aefce14610088578063a9b4b78014610083578063eaa0e30e1461007e5780630b71614814610079578063c75ebb82146100745763becc653b1461006f575f80fd5b6101a9565b61017f565b610175565b61014c565b61013e565b610130565b50610096610205565b005b6101ca565b506100a6610381565b6001600160a01b0319811661012c576100bd61038f565b906100c661039d565b916100cf6103ab565b6100d76103b9565b90606483602802049481610114575b50505082811061010c575b505f6020525f5260405f209080825492556001540103600155005b91505f6100f1565b91603c916064939694960204020401915f80806100e6565b5f80fd5b602038601f19015f3960205ff35b602038603f19015f3960205ff35b610154610381565b6001600160a01b0319811661012c575f6020525f5260405f20545f5260205ff35b6001545f5260205ff35b610187610381565b6001600160a01b0319811661012c5760096020525f5260405f20545f5260205ff35b6101b1610381565b5f8051602061040183398151915201545f908152602090f35b6101d2610381565b6001600160a01b0319811661012c575f6020525f5260405f205460026020526064602860405f2054020490045f5260205ff35b61020d6103c7565b6004545f805160206104018339815191528101545f60208190528381526040902090919054906001805460065f528260205f200154948042116102ec575b505050600190810160045560058054808301909155425f80516020610401833981519152909101556006805491820190557ff652222313e28459528d920b65115c16c04f3efc82aaedc97be59f3f377c0d3f0182905560096020525f838152604090208054670de0b6b3a76400006102cb8660076020525f5260405f2090565b93845486030204019055556102e9429160086020525f5260405f2090565b55565b809162093a8080808094010402904291428110610379575b5061030d6103e4565b916103166103f2565b5f93831515965b6101f48610610332575b50505050505061024b565b87610366575b504283146103605787868401954296428110610358575b5001949261031d565b96505f61034f565b80610327565b830381830202849004909a01995f610338565b91505f610304565b6024361061012c5760043590565b6044361061012c5760243590565b6064361061012c5760443590565b6084361061012c5760643590565b60a4361061012c5760843590565b6024361061012c57600435906001600160a01b0319821661012c57565b602038601f19015f395f5190565b602038603f19015f395f519056fe036b6384b5eca791c62761152d0c79bb0604c104a5fb6f4eb0703f3154bb3db0";
        address deployed = deployFromBytecode(bytecode);

        rewardAccumulation = IRewardAccumulation(deployed);
    }

    function testContractDeploy() public view {
        assert(address(rewardAccumulation) != address(0));
    }

    function testRate() public view {
        uint256 rate = rewardAccumulation.getRate();
        assert(rate == s_rate);
    }

    function testWeight() public view {
        uint256 weight = rewardAccumulation.getWeight();
        assert(weight == s_weight);
    }

    function testWorkingSupply() public view {
        uint256 ws = rewardAccumulation.getWorkingSupply();
        assert(ws == 0);
    }

    function testPeriodTimestamp() public view {
        uint256 t = rewardAccumulation.getPeriodTimestamp(0);
        assert(t == block.timestamp);
    }

    function testGetUserWb() public view {
        uint256 wb = rewardAccumulation.getUserWb(address(this));
        assert(wb == 0);
    }

    function testGetUserReward() public view {
        uint256 ur = rewardAccumulation.getUserReward(address(this));
        assert(ur == 0);
    }

    function testGetUserBoostFactor() public view {
        uint256 ubf = rewardAccumulation.getBoostFactor(address(this));
        assert(ubf == 0);
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

    function deployFromBytecode(
        bytes memory bytecode
    ) public returns (address addr) {
        assembly {
            // `bytecode` is in memory:
            // - first 32 bytes at `bytecode` is length
            // - actual code starts at `add(bytecode, 32)`
            addr := create(0, add(bytecode, 32), mload(bytecode))
        }
    }
}
