// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StakingGraph} from "./StakingGraph.sol";

contract StakingGraphTest is Test {
    using StakingGraph for StakingGraph.Graph;

    StakingGraph.Graph private graph;


    // Helper function to calculate expected stake amount
    function calculateExpectedStake(
        int256 amount,
        uint256 start,
        uint256 duration,
        uint256 queryStart,
        uint256 queryDuration
    ) internal pure returns (int256) {

        /**
          Stake time range: start|-------------------------------------|end
          Query time range: qS|--------------------------------------------|qE

          qS: queryStart
          qE: queryEnd
         */
        if(queryStart < start && queryStart + queryDuration >= start + duration){
            queryDuration = 5_256_000;
            
        /**
          Stake time range: start|-------------------------------------|end
          Query time range: qS|----------------------|qE
         */
        } else if (queryStart < start && queryStart + queryDuration <= start + duration && queryStart + queryDuration >= start) {
            // Query starts before stake and ends during stake
            // queryDuration = (queryStart to queryEnd) - (queryStart to stakeStart)
            queryDuration = (queryStart + queryDuration) - start;
                        
        /**
          Query is outside staking range
          Stake time range:            start|-------------------------------------|end
          Query time range: qS|--------|qs + qD           ||                         qS|--------|qE
         */
        } else if ((queryStart < start && queryStart + queryDuration < start) || (queryStart >= start + duration)) {
            // Query is completely outside stake range
            queryDuration = 0;
            
        /**
          Stake time range: start|-------------------------------------|end
          Query time range:            qS|--------------------------------------|qE
         */
        } else if (queryStart >= start && queryStart + queryDuration >= start + duration) {
            // Query starts during stake and ends after stake
            // queryDuration = (stakeEnd - queryStart)
            queryDuration = (start + duration) - queryStart;
            
        /**
          Stake time range: start|-------------------------------------|end
          Query time range:           qS|-------------------|qE
         */
        } else {
            // Query is completely within stake range
            queryDuration = queryDuration;
        }
        
        // Calculate number of blocks in the query range
        uint256 blocksInRange = queryDuration;
        
        // Return total stake in the range
        return amount * int256(blocksInRange);
    }

    
    // Test basic stake addition and querying
    // forge test --match-test testFuzzBasicStake --fuzz-runs 1000000 -vv
    function testFuzzBasicStake(
        int256 amount,
        uint256 start,
        uint256 queryStart,
        uint256 queryDuration
    ) public {
        uint256 duration = 5_256_000;

        // Constrain inputs to reasonable ranges
        vm.assume(amount > 1e13 && amount <= 500e18); // enforcing practical bound close to real world values
        vm.assume(start > 0 && start < 42e8);
        vm.assume(queryStart > 0 && queryStart < type(uint16).max);
        vm.assume(queryDuration > 0 && queryDuration < type(uint16).max);
        
        // Ensure query range is within stake range
        vm.assume(queryStart > start);
        vm.assume(queryStart + queryDuration <= start + duration);

        // Add stake
        graph.addStake(amount, start, duration);

        // Query stake
        int256 expectedStake = calculateExpectedStake(amount, start, duration, queryStart, queryDuration);
        int256 actualStake = graph.queryStake(queryStart + 1, queryStart + queryDuration);

        assertApproxEqAbs(actualStake, expectedStake, 1, "Stake query result mismatch");
    }


    // forge test --match-test testPoCBasicStake --fuzz-runs 1000000 -vv
    // args=[701023384003508 [7.01e14], 1, 1614704 [1.614e8], 860090 [8.6e8]]]
    // args=[73191574236380 [7.319e13], 1, 4111237560303046523516261403049160 [4.111e33], 115792089237316195423570985008687907853269984665640564039457584007913129639932 [1.157e77]]] 
    function testPoCBasicStake() public {
        
        uint256 duration = 5_256_000;

        int256 amount = 73191574236380;
        // uint256 start = 4294967290; // This passes
        // addStake reverts with [FAIL: EvmError: Revert] once the start is >= 4300000000
        // This because of the require statement "require(start < GRAPH_MAX-1)" which is triggered once start is too large
        /**
         However this isn't a threat as it will take multiple years for the block.number of supported chains to hit this limit 

         **Ethereum**
            Latest blocks: 22425112
            Blocks time: 12sec
            Blocks left: 4300000000 - 22425112 = 4277574888
            Time left (in seconds): 4277574888 * 12 = 51330898656
            Time left (in days): 51330898656 / 86400 = 594107
            Time left (in years): 594107 / 365 = 1627 years

            Optimism
            Latest blocks: 135581598
            Blocks time: 2sec
            Blocks left: 4300000000 - 135581598 = 4164418402
            Time left (in seconds): 3966132020 * 2 = 7932264040
            Time left (in days): 7932264040 / 86400 = 91808
            Time left (in years): 91808 / 365 = 251.5 years

            **Arbitrum**
            Latest blocks: 333867980
            Blocks time: 0.25sec
            Blocks left: 4300000000 - 333867980 = 3966132020
            Time left (in seconds): 3966132020 * 0.25 = 991533005
            Time left (in days): 991533005 / 86400 = 11476
            Time left (in years): 11476 / 365 = 31.4 years
         */
        uint256 start = 4200000000;
        uint256 queryStart = 1614704;
        uint256 queryDuration = 860090;

        // Add stake
        graph.addStake(amount, start, duration);

        // Query stake
        int256 expectedStake = calculateExpectedStake(amount, start, duration, queryStart, queryDuration);
        int256 actualStake = graph.queryStake(queryStart + 1, queryStart + queryDuration);

        console.log("expectedStake:", expectedStake);
        console.log("actualStake:", actualStake);

        assertApproxEqAbs(actualStake, expectedStake, 1, "Stake query result mismatch");
    }


    // Test multiple overlapping stakes
    // forge test --match-test testMultipleStakes --fuzz-runs 1000000 -vv
    function testMultipleStakes(
        int256 amount1,
        int256 amount2,
        uint256 start1,
        uint256 start2,
        uint256 queryStart,
        uint256 queryDuration
    ) public {
        uint256 duration = 5_256_000;


        // Constrain inputs to reasonable ranges
        vm.assume(amount1 > 0 && amount1 <= 5000e18);
        vm.assume(amount2 > 0 && amount2 <= 5000e18);
        vm.assume(start1 > 0 && start1 < 42e8);
        vm.assume(start2 > 0 && start2 < 42e8);
        vm.assume(queryStart > 0 && queryStart < type(uint16).max);
        vm.assume(queryDuration > 0 && queryDuration < type(uint16).max);

        // Ensure query range is within stake range
        if (start2 > start1) {
            vm.assume(queryStart > start1);
            vm.assume(queryStart + queryDuration <= start2 + duration);
        } else {
            vm.assume(queryStart > start2);
            vm.assume(queryStart + queryDuration <= start1 + duration);
        }

        // Add first stake
        graph.addStake(amount1, start1, duration);
        
        // Add second stake
        graph.addStake(amount2, start2, duration);

        // Calculate expected total stake
        int256 expectedStake1 = calculateExpectedStake(amount1, start1, duration, queryStart, queryDuration);
        int256 expectedStake2 = calculateExpectedStake(amount2, start2, duration, queryStart, queryDuration);
        int256 expectedTotalStake = expectedStake1 + expectedStake2;

        // Query total stake
        int256 actualStake = graph.queryStake(queryStart + 1, queryStart + queryDuration);

        assertApproxEqAbs(actualStake, expectedTotalStake, 1, "Multiple stakes query result mismatch");
    }



    // forge test --match-test testPoCMultipleStakes --fuzz-runs 1000000 -vv
    // args=[100000000000000000000 [1e20], 500000000000000000000 [5e20], 340, 12170 [1.217e4], 3084, 11959 [1.195e4]]]
    function testPoCMultipleStakes() public {
        uint256 duration = 5_256_000;

        int256 amount1 = 100000000000000000000;
        int256 amount2 = 500000000000000000000;
        uint256 start1 = 340;
        uint256 start2 = 12170;
        uint256 queryStart = 3084;
        uint256 queryDuration = 11959;

        // Add first stake
        graph.addStake(amount1, start1, duration);
        
        // Add second stake
        graph.addStake(amount2, start2, duration);

        // Calculate expected total stake
        int256 expectedStake1 = calculateExpectedStake(amount1, start1, duration, queryStart, queryDuration);
        int256 expectedStake2 = calculateExpectedStake(amount2, start2, duration, queryStart, queryDuration);
        int256 expectedTotalStake = expectedStake1 + expectedStake2;

        // Query total stake
        int256 actualStake = graph.queryStake(queryStart + 1, queryStart + queryDuration);

        console.log("expectedStake1:", expectedStake1);
        console.log("expectedStake2:", expectedStake2);
        console.log("expectedTotalStake:", expectedTotalStake);
        console.log("actualStake:", actualStake);

        assertApproxEqAbs(actualStake, expectedTotalStake, 1, "Multiple stakes query result mismatch");

        /**
        Logs:
            expectedStake1: 1195900000000000000000000
            expectedStake2: 1436500000000000000000000            
            expectedTotalStake: 2632400000000000000000000
            actualStake: 2632400000000000000000000 
         */
    }

    // Test stake removal (negative amount)
    // forge test --match-test testFuzzStakeRemoval --fuzz-runs 1000000 -vv
    function testFuzzStakeRemoval(
        int256 initialAmount1,
        int256 initialAmount2,
        int256 removalAmount1,
        int256 removalAmount2,
        uint256 start1,
        uint256 start2,
        uint256 queryStart,
        uint256 queryDuration
    ) public {
        uint256 duration = 5_256_000;

        // Constrain inputs to reasonable ranges
        vm.assume(initialAmount1 > 2e13 && initialAmount1 <= 500e18);
        vm.assume(initialAmount2 > 2e13 && initialAmount2 <= 500e18);
        vm.assume(removalAmount1 > 0 && removalAmount1 <= initialAmount1);
        vm.assume(removalAmount2 > 0 && removalAmount2 <= initialAmount2);
        vm.assume(start1 > 0 && start1 < 42e8);
        vm.assume(start2 > 0 && start2 < 42e8);
        vm.assume(queryStart > 0 && queryStart < type(uint16).max);
        vm.assume(queryDuration > 0 && queryDuration < type(uint16).max);

        // Ensure query range is within stake ranges
        if (start2 > start1) {
            vm.assume(queryStart > start1);
            vm.assume(queryStart + queryDuration <= start2 + duration);
        } else {
            vm.assume(queryStart > start2);
            vm.assume(queryStart + queryDuration <= start1 + duration);
        }

        // Add first stake
        graph.addStake(initialAmount1, start1, duration);
        
        // Add second stake
        graph.addStake(initialAmount2, start2, duration);

        // Remove portion of first stake
        graph.addStake(-removalAmount1, start1, duration);
        
        // Remove portion of second stake
        graph.addStake(-removalAmount2, start2, duration);

        // Calculate expected remaining stakes
        int256 expectedStake1 = calculateExpectedStake(initialAmount1 - removalAmount1, start1, duration, queryStart, queryDuration);
        int256 expectedStake2 = calculateExpectedStake(initialAmount2 - removalAmount2, start2, duration, queryStart, queryDuration);

        int256 expectedTotalStake = expectedStake1 + expectedStake2;

        // Query total remaining stake
        int256 actualStake = graph.queryStake(queryStart + 1, queryStart + queryDuration);

        console.log("expectedStake1:", expectedStake1);
        console.log("expectedStake2:", expectedStake2);
        console.log("expectedTotalStake:", expectedTotalStake);
        console.log("actualStake:", actualStake);

        assertApproxEqAbs(actualStake, expectedTotalStake, 1, "Multiple stakes removal query result mismatch");
    }

    // forge test --match-test testPoCStakeRemoval --fuzz-runs 1000000 -vv
    function testPoCStakeRemoval() public {
        uint256 duration = 5_256_000;

        int256 initialAmount1 = 100000000000000000000;  // 100 tokens
        int256 initialAmount2 = 500000000000000000000;  // 500 tokens
        int256 removalAmount1 = 30000000000000000000;   // 30 tokens
        int256 removalAmount2 = 200000000000000000000;  // 200 tokens
        uint256 start1 = 340;
        uint256 start2 = 12170;
        uint256 queryStart = 3084;
        uint256 queryDuration = 11959;

        // Add first stake
        graph.addStake(initialAmount1, start1, duration);
        
        // Add second stake
        graph.addStake(initialAmount2, start2, duration);

        // Remove portion of first stake
        graph.addStake(-removalAmount1, start1, duration);
        
        // Remove portion of second stake
        graph.addStake(-removalAmount2, start2, duration);

        // Calculate expected remaining stakes
        int256 expectedStake1 = calculateExpectedStake(initialAmount1 - removalAmount1, start1, duration, queryStart, queryDuration);
        int256 expectedStake2 = calculateExpectedStake(initialAmount2 - removalAmount2, start2, duration, queryStart, queryDuration);
        int256 expectedTotalStake = expectedStake1 + expectedStake2;

        // Query total remaining stake
        int256 actualStake = graph.queryStake(queryStart + 1, queryStart + queryDuration);

        console.log("expectedStake1:", expectedStake1);
        console.log("expectedStake2:", expectedStake2);
        console.log("expectedTotalStake:", expectedTotalStake);
        console.log("actualStake:", actualStake);

        assertApproxEqAbs(actualStake, expectedTotalStake, 1, "Multiple stakes removal query result mismatch");
        /**
            Logs:
                expectedStake1: 837130000000000000000000
                expectedStake2: 861900000000000000000000
                expectedTotalStake: 1699030000000000000000000
                actualStake: 1699030000000000000000000
         */
    }

}