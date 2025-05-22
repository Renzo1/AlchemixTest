// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PositionDecay} from "./PositionDecay.sol";

contract PositionDecayTest is Test {

    // forge test --match-test testFuzzCase1 --fuzz-runs 1000000 -vv
    function testFuzzCase1(uint256 initialCollateral, uint256 debt) public {

    }

    // forge test --match-test testFuzzWeightDecay --fuzz-runs 1000000 -vv
    function testFuzzWeightDecay(
        uint256 total,
        uint256 increment,
        uint256 userValue
    ) public {
        // Constrain inputs to valid ranges
        vm.assume(total > 0);
        vm.assume(total <= type(uint128).max);
        vm.assume(increment <= total);
        vm.assume(userValue <= total); // User value cannot exceed total
        
        // Initialize user's last weight at 0
        uint256 userLastWeight = 0;
        
        // Calculate the new weight increment
        uint256 weightIncrement = PositionDecay.WeightIncrement(increment, total);
        
        // Calculate the weight delta for the user
        uint256 currentWeight = weightIncrement;
        uint256 weightDelta = currentWeight - userLastWeight;
        
        // Calculate the expected decayed value
        uint256 decayedValue = PositionDecay.ScaleByWeightDelta(userValue, weightDelta);
        
        // Verify properties:
        
        // 1. If increment is 0, weightIncrement should be 0
        if (increment == 0) {
            assertEq(weightIncrement, 0, "Weight increment should be 0 when increment is 0");
        }
        
        // 2. If weightDelta is 0, decayedValue should be 0
        if (weightDelta == 0) {
            assertEq(decayedValue, 0, "Decayed value should be 0 when weight delta is 0");
        }
        
        // 3. The decayed value should never be greater than the original value
        assertLe(decayedValue, userValue, "Decayed value should never be greater than original value");
        
        // // 4. If increment equals total, the weight should be maximum
        // if (increment == total) {
        //     assertGt(weightIncrement, 0, "Weight increment should be positive when increment equals total");
        // }
        
        // 5. The decay should be proportional to the increment/total ratio
        if (increment > 0 && total > 0) {
            uint256 ratio = (increment * 1e18) / total;
            uint256 expectedDecay = (userValue * ratio) / 1e18;
            
            vm.assume(ratio > 0);
            vm.assume(expectedDecay > 0);

            // assertApproxEqAbs(
            //     decayedValue,
            //     expectedDecay,
            //     1, // 1e16 1% tolerance
            //     "Decay should be proportional to increment/total ratio"
            // );

            // Verify the ratio between increment/total equals decayedValue/userValue
            uint256 decayRatio = (decayedValue * 1e18) / userValue;
            // assertApproxEqAbs(
            //     ratio,
            //     decayRatio,
            //     1,
            //     "Ratio between increment/total should equal decayedValue/userValue"
            // );

            // assertLe(decayedValue - expectedDecay, 1, "Decay should be proportional to increment/total ratio");

        }

        
        //////////// Other Users Accounting ////////////////

        uint256 otherUsersValue = total - userValue;

        // Initialize user's last weight at 0
        uint256 user2LastWeight = 0;
        
        // Calculate the weight delta for the user
        uint256 user2WeightDelta = currentWeight - user2LastWeight;

        uint256 user2DecayedValue = PositionDecay.ScaleByWeightDelta(otherUsersValue, user2WeightDelta);

        console.log("user2DecayedValue:", user2DecayedValue);

        // Assert sum of decayed values equals increment
        console.log("user2DecayedValue + decayedValue:", user2DecayedValue + decayedValue);
        console.log("increment:", increment);
        // assertGe(user2DecayedValue + decayedValue, increment, "Sum of decayed values is always greater than or equal to increment");
        assertApproxEqAbs(user2DecayedValue + decayedValue, increment, 1e3, "Sum of decayed values should equal increment");
    }



    // forge test --match-test testFuzzComplexWeightDecay --fuzz-runs 1000000 -vv
    function testFuzzComplexWeightDecay(
        uint256 initialTotal,
        uint256 increments0,
        uint256 increments1,
        uint256 increments2,
        uint256 userValue
    ) public {
        // Constrain inputs to valid ranges
        vm.assume(initialTotal > 0);
        vm.assume(initialTotal <= type(uint128).max);
        vm.assume(userValue <= initialTotal); // User value cannot exceed total
        vm.assume(increments0 <= type(uint128).max / 4);
        vm.assume(increments1 <= type(uint128).max / 4);
        vm.assume(increments2 <= type(uint128).max / 4);
        vm.assume(increments0 + increments1 + increments2 <= initialTotal);
        // vm.assume(increments0 + increments1 + increments2 <= type(uint128).max);

        uint256[] memory increments = new uint256[](3);
        increments[0] = increments0;
        increments[1] = increments1;
        increments[2] = increments2;

        uint256 totalIncrement = increments[0] + increments[1] + increments[2];
        
        // Initialize tracking variables
        uint256 currentTotal = initialTotal;
        uint256 currentWeight = 0;
        uint256 userLastWeight = 0;
        uint256 currentUserValue = userValue;
        
        // Process each increment
        for (uint256 i = 0; i < increments.length; i++) {
            // Constrain increment
            vm.assume(increments[i] <= currentTotal);
            
            // Calculate weight increment for this step
            uint256 weightIncrement = PositionDecay.WeightIncrement(increments[i], currentTotal);
            
            // Update current weight
            currentWeight += weightIncrement;
            
            // Calculate weight delta for user
            uint256 weightDelta = currentWeight - userLastWeight;
            
            // Update user's value with decay
            uint256 decayedValue = PositionDecay.ScaleByWeightDelta(currentUserValue, weightDelta);

            
            // Update total and user's last weight
            currentTotal -= increments[i];
            userLastWeight = currentWeight;
            currentUserValue -= decayedValue;
            
            // Verify properties after each step
            
            // 1. User value should never exceed current total
            assertLe(currentUserValue, currentTotal, "User value should never exceed current total");
            
            // 2. Current weight should be cumulative
            assertGe(currentWeight, userLastWeight, "Current weight should be cumulative");
            
            // 3. Weight delta should be positive
            // assertGe(weightDelta, 0, "Weight delta should be positive");
            
            // 4. The decay should be proportional to the increment/total ratio
            uint256 oldTotal = currentTotal + increments[i];
            uint256 oldUserValue = currentUserValue + decayedValue;
            // if (increments[i] > 0 && oldTotal > 0) {
            //     uint256 ratio = (increments[i] * 1e18) / oldTotal;
            //     uint256 expectedDecay = (oldUserValue * ratio) / 1e18;

            //     vm.assume(ratio > 0);
            //     vm.assume(expectedDecay > 0);

            //     // assertApproxEqAbs(
            //     //     decayedValue,
            //     //     expectedDecay,
            //     //     1, 
            //     //     "Decay should be proportional to increment/total ratio"
            //     // );

            //     // Verify the ratio between increment/total equals decayedValue/userValue
            //     uint256 decayRatio = (decayedValue * 1e18) / oldUserValue;
            //     // assertApproxEqAbs(
            //     //     ratio,
            //     //     decayRatio,
            //     //     1,
            //     //     "Ratio between increment/total should equal decayedValue/userValue"
            //     // );

            //     // assertLe(decayedValue - expectedDecay, 1, "Decay should be proportional to increment/total ratio");

            // }
            
            // 5. If increment is 0, weight increment should be 0
            if (increments[i] == 0) {
                assertEq(weightIncrement, 0, "Weight increment should be 0 when increment is 0");
            }
            
            // // 6. If increment equals current total, weight should be maximum
            // if (increments[i] == currentTotal) {
            //     assertEq(weightIncrement, 0, "Weight increment should be positive when increment equals total");
            // }
        }
        
        // Final verification
        assertLe(currentUserValue, userValue, "Final user value should not exceed initial value");
        // assertGe(currentWeight, 0, "Final weight should be non-negative");
        assertLe(currentTotal, initialTotal, "Final total should not exceed initial total");


                
        //////////// Other Users Accounting ////////////////

        uint256 otherUsersInitialValue = initialTotal - userValue;

        // Initialize user's last weight at 0
        uint256 user2LastWeight = 0;
        
        // Calculate the weight delta for the user
        uint256 user2WeightDelta = currentWeight - user2LastWeight;

        uint256 user2DecayedValue = PositionDecay.ScaleByWeightDelta(otherUsersInitialValue, user2WeightDelta);

        uint256 otherUsersCurrentValue = otherUsersInitialValue - user2DecayedValue;
        user2LastWeight = currentWeight;

        /// Assertion
        // the ration between userValue/otherUsersInitialValue should be the same as the ratio between currentUserValue/otherUsersCurrentValue
        uint256 ratio_1 = (userValue * 1e18) / otherUsersInitialValue;
        uint256 ratio_2 = (currentUserValue * 1e18) / otherUsersCurrentValue;

        console.log("ratio_1:", ratio_1);
        console.log("ratio_2:", ratio_2);

        assertApproxEqAbs(ratio_1, ratio_2, 1, "The ratio between userValue/otherUsersInitialValue should be the same as the ratio between currentUserValue/otherUsersCurrentValue");
    }









    // forge test --match-test testFuzzDecay0PoC -vv
    /**
     counterexample: 
        args=[65711888983981875328876342570773043794 [6.571e37], 28121750387658846337752471388 [2.812e28], 44744369737397 [4.474e13]]]
     */
    function testFuzzDecay0PoC() public {
        uint256 total = 65711888983981875328876342570773043794;
        uint256 increment = 28121750387658846337752471388;
        uint256 userValue = 44744369737397;

        // Constrain inputs to valid ranges
        vm.assume(total > 0);
        vm.assume(total <= type(uint128).max);
        vm.assume(increment <= total);
        vm.assume(userValue <= total); // User value cannot exceed total
        
        // Initialize user's last weight at 0
        uint256 userLastWeight = 0;
        uint256 currentWeight = 0;
        
        // Calculate the new weight increment
        uint256 weightIncrement = PositionDecay.WeightIncrement(increment, total);
        
        // Calculate the weight delta for the user
        currentWeight += weightIncrement;
        uint256 weightDelta = currentWeight - userLastWeight;
        
        // Calculate the expected decayed value
        uint256 decayedValue = PositionDecay.ScaleByWeightDelta(userValue, weightDelta);
        
        // Verify properties:
        
        // 1. If increment is 0, weightIncrement should be 0
        if (increment == 0) {
            assertEq(weightIncrement, 0, "Weight increment should be 0 when increment is 0");
        }
        
        // 2. If weightDelta is 0, decayedValue should be 0
        if (weightDelta == 0) {
            assertEq(decayedValue, 0, "Decayed value should be 0 when weight delta is 0");
        }
        
        // 3. The decayed value should never be greater than the original value
        assertLe(decayedValue, userValue, "Decayed value should never be greater than original value");
        
        // // 4. If increment equals total, the weight should be maximum
        // if (increment == total) {
        //     assertGt(weightIncrement, 0, "Weight increment should be positive when increment equals total");
        // }
        
        // 5. The decay should be proportional to the increment/total ratio
        if (increment > 0 && total > 0) {
            uint256 ratio = (increment * 1e18) / total;
            uint256 expectedDecay = (userValue * ratio) / 1e18;

            vm.assume(ratio > 0);
            vm.assume(expectedDecay > 0);

            console.log("expectedDecay:", expectedDecay);
            console.log("decayedValue:", decayedValue);
            console.log("----------------------------------------------");
            
            // assertApproxEqAbs(
                //     decayedValue,
                //     expectedDecay,
                //     1, // 1% tolerance
                //     "Decay should be proportional to increment/total ratio"
                // );
                
                // Verify the ratio between increment/total equals decayedValue/userValue
                uint256 decayRatio = (decayedValue * 1e18) / userValue;
                
                console.log("total ratio:", ratio);
                console.log("decayRatio:", decayRatio);

                // assertApproxEqAbs(
                //     ratio,
                //     decayRatio,
                //     1,
                //     "Ratio between increment/total should equal decayedValue/userValue"
                // );
                
                // assertLe(decayedValue - expectedDecay, 1, "Decay should be proportional to increment/total ratio");

        }

        //////////// Other Users Accounting ////////////////

        uint256 otherUsersValue = total - userValue;

        // Initialize user's last weight at 0
        uint256 user2LastWeight = 0;
        
        // Calculate the weight delta for the user
        uint256 user2WeightDelta = currentWeight - user2LastWeight;

        uint256 user2DecayedValue = PositionDecay.ScaleByWeightDelta(otherUsersValue, user2WeightDelta);

        console.log("user2DecayedValue:", user2DecayedValue);

        // Assert sum of decayed values equals increment
        console.log("user2DecayedValue + decayedValue:", user2DecayedValue + decayedValue);
        console.log("increment:", increment);
        assertGt(user2DecayedValue + decayedValue, increment, "Sum of decayed values can be greater than increment");

        
        /**
         Logs:
            expectedDecay: 2602347054419317                      
            decayedValue: 2602347054419685
            ----------------------------------------------       
            total ratio: 6121604862441                           
            decayRatio: 6121604862441
            user2DecayedValue: 559241683503294329475235492
            user2DecayedValue + decayedValue: 559241683505896676529655177
            increment: 559241683505896676529655176
         */
    }






    struct PocParams {
        uint256 initialTotal;
        uint256[] increments;
        uint256 userValue;

        uint256 totalIncrement;
        uint256 currentTotal;
        uint256 currentWeight;
        uint256 userLastWeight;
        uint256 currentUserValue;

        uint256 otherUsersInitialValue;
        uint256 user2LastWeight;
        uint256 user2WeightDelta;
        uint256 user2DecayedValue;
        uint256 otherUsersCurrentValue;
        uint256 userAPercentChange;
        uint256 otherUsersPercentChange;
        uint256 ratio_1;
        uint256 ratio_2;

    }

    // forge test --match-test testFuzzComplexWeightDecayPoC -vv

    /*
    args=[23489 [2.348e4], 10310 [1.031e4], 671, 1723, 479]] 
    */
    function testFuzzComplexWeightDecayPoC() public {
        PocParams memory params;


        params.initialTotal = 23489;
        params.increments = new uint256[](3);
        params.increments[0] = 10310;
        params.increments[1] = 671;
        params.increments[2] = 1723;
        params.userValue = 479;

        params.totalIncrement = params.increments[0] + params.increments[1] + params.increments[2];

        // Constrain inputs to valid ranges
        vm.assume(params.initialTotal > 0);
        vm.assume(params.initialTotal <= type(uint128).max);
        vm.assume(params.userValue <= params.initialTotal); // User value cannot exceed total
        vm.assume(params.totalIncrement <= params.initialTotal);
        // vm.assume(params.increments[0] + params.increments[1] + params.increments[2] <= type(uint128).max);

        
        // Initialize tracking variables
        params.currentTotal = params.initialTotal;
        params.currentWeight = 0;
        params.userLastWeight = 0;
        params.currentUserValue = params.userValue;
        
        // Process each increment
        for (uint256 i = 0; i < params.increments.length; i++) {
            // Constrain increment
            vm.assume(params.increments[i] <= params.currentTotal);
            
            // Calculate weight increment for this step
            uint256 weightIncrement = PositionDecay.WeightIncrement(params.increments[i], params.currentTotal);
            
            // Update current weight
            params.currentWeight += weightIncrement;
            
            // Calculate weight delta for user
            uint256 weightDelta = params.currentWeight - params.userLastWeight;
            
            // Update user's value with decay
            uint256 decayedValue = PositionDecay.ScaleByWeightDelta(params.currentUserValue, weightDelta);

            
            // Update total and user's last weight
            params.currentTotal -= params.increments[i];
            params.userLastWeight = params.currentWeight;
            params.currentUserValue -= decayedValue;
            
            // Verify properties after each step
            
            // 1. User value should never exceed current total
            assertLe(params.currentUserValue, params.currentTotal, "User value should never exceed current total");
            
            // 2. Current weight should be cumulative
            assertGe(params.currentWeight, params.userLastWeight, "Current weight should be cumulative");
            
            // 3. Weight delta should be positive
            // assertGe(weightDelta, 0, "Weight delta should be positive");
            
            // 4. The decay should be proportional to the increment/total ratio
            uint256 oldTotal = params.currentTotal + params.increments[i];
            uint256 oldUserValue = params.currentUserValue + decayedValue;

            
            // 5. If increment is 0, weight increment should be 0
            if (params.increments[i] == 0) {
                assertEq(weightIncrement, 0, "Weight increment should be 0 when increment is 0");
            }
            
            // // 6. If increment equals current total, weight should be maximum
            // if (increments[i] == currentTotal) {
            //     assertEq(weightIncrement, 0, "Weight increment should be positive when increment equals total");
            // }
        }
        
        // Final verification
        assertLe(params.currentUserValue, params.userValue, "Final user value should not exceed initial value");
        // assertGe(currentWeight, 0, "Final weight should be non-negative");
        assertLe(params.currentTotal, params.initialTotal, "Final total should not exceed initial total");


                
        //////////// Other Users Accounting ////////////////

        params.otherUsersInitialValue = params.initialTotal - params.userValue;

        // Initialize user's last weight at 0
        params.user2LastWeight = 0;
        
        // Calculate the weight delta for the user
        params.user2WeightDelta = params.currentWeight - params.user2LastWeight;

        params.user2DecayedValue = PositionDecay.ScaleByWeightDelta(params.otherUsersInitialValue, params.user2WeightDelta);

        params.otherUsersCurrentValue = params.otherUsersInitialValue - params.user2DecayedValue;
        params.user2LastWeight = params.currentWeight;

        /// Assertion
        // the ration between userValue/otherUsersInitialValue should be the same as the ratio between currentUserValue/otherUsersCurrentValue
        params.ratio_1 = (params.userValue * 1e18) / params.otherUsersInitialValue;
        params.ratio_2 = (params.currentUserValue * 1e18) / params.otherUsersCurrentValue;

        console.log("ratio_1:", params.ratio_1);
        console.log("ratio_2:", params.ratio_2);
        /**
         Logs:
            ratio_1: 20817036071273359
            ratio_2: 20728821580690960

            Ratio_1 (initial values) is bigger than Ratio_2 (current value), which means User A was more impacted by the decay than User B, because their value decreased more.
            Lower decay value --> higher current value --> higher current value for other users --> lower ratio
            
        */

        //// Calculating the % difference in between cost burden on UserA and other Users
        /**
         % change = (newValue - oldValue) / oldValue * 100 
         
         but to avoid underfllow, we use:
         diff = newValue > oldValue ? newValue - oldValue : oldValue - newValue;
         percentChange = (diff * 100) / oldValue;
         */

        params.userAPercentChange = (params.userValue - params.currentUserValue) * 1e18 / params.userValue;
        params.otherUsersPercentChange = (params.otherUsersInitialValue - params.otherUsersCurrentValue) * 1e18 / params.otherUsersInitialValue;

        // Calculate the absolute difference between the two percent changes
        uint256 rawDiff = (params.userAPercentChange > params.otherUsersPercentChange) 
            ? params.userAPercentChange - params.otherUsersPercentChange 
            : params.otherUsersPercentChange - params.userAPercentChange;

        // Calculate the percentage difference
        uint256 percentageDifference = (rawDiff * 1e18) / params.userAPercentChange;

        console.log("userAPercentChange:", params.userAPercentChange);
        console.log("otherUsersPercentChange:", params.otherUsersPercentChange);
        console.log("rawDiff:", rawDiff);
        console.log("percentageDifference:", percentageDifference);
        console.log("userAPercentChange is bigger than otherUsersPercentChange:", params.userAPercentChange > params.otherUsersPercentChange);

        assertApproxEqAbs(params.userAPercentChange, params.otherUsersPercentChange, 1, "The ratio between userValue/otherUsersInitialValue should be the same as the ratio between currentUserValue/otherUsersCurrentValue");

        /*
        Logs:
            ratio_1: 20817036071273359
            ratio_2: 20728821580690960
            userAPercentChange: 542797494780793319
            otherUsersPercentChange: 540851803563667970
            rawDiff: 1945691217125349 (1.94e15) // 0.194%
            percentageDifference: 3584561896165546 (3.58e15) // 0.358%
            userAPercentChange is bigger than otherUsersPercentChange: true


            This means that User A's cost burden is 0.358% higher than User B's. 
            This is bad for the protocol because it means that User A is paying more for the same service, and User B is paying less for engaging with the protocol less, 
            which discourages users to engage with the protocol.
        */
    }




































    
    // forge test --match-test testFuzzDecayPoC -vv
    /**
     counterexample: 
        args=args=[91355403700920895347087577273262 [9.135e31], 559241683505896676529655176 [5.592e26], 425108629664415777436 [4.251e20]]]
     */
    function testFuzzDecayPoC() public {
        uint256 total = 91355403700920895347087577273262;
        uint256 increment = 559241683505896676529655176;
        uint256 userValue = 425108629664415777436;

        // Constrain inputs to valid ranges
        vm.assume(total > 0);
        vm.assume(total <= type(uint128).max);
        vm.assume(increment <= total);
        vm.assume(userValue <= total); // User value cannot exceed total
        
        // Initialize user's last weight at 0
        uint256 userLastWeight = 0;
        uint256 currentWeight = 0;
        
        // Calculate the new weight increment
        uint256 weightIncrement = PositionDecay.WeightIncrement(increment, total);
        
        // Calculate the weight delta for the user
        currentWeight += weightIncrement;
        uint256 weightDelta = currentWeight - userLastWeight;
        
        // Calculate the expected decayed value
        uint256 decayedValue = PositionDecay.ScaleByWeightDelta(userValue, weightDelta);
        
        // Verify properties:
        
        // 1. If increment is 0, weightIncrement should be 0
        if (increment == 0) {
            assertEq(weightIncrement, 0, "Weight increment should be 0 when increment is 0");
        }
        
        // 2. If weightDelta is 0, decayedValue should be 0
        if (weightDelta == 0) {
            assertEq(decayedValue, 0, "Decayed value should be 0 when weight delta is 0");
        }
        
        // 3. The decayed value should never be greater than the original value
        assertLe(decayedValue, userValue, "Decayed value should never be greater than original value");
        
        // // 4. If increment equals total, the weight should be maximum
        // if (increment == total) {
        //     assertGt(weightIncrement, 0, "Weight increment should be positive when increment equals total");
        // }
        
        // 5. The decay should be proportional to the increment/total ratio
        if (increment > 0 && total > 0) {
            uint256 ratio = (increment * 1e18) / total;
            uint256 expectedDecay = (userValue * ratio) / 1e18;

            vm.assume(ratio > 0);
            vm.assume(expectedDecay > 0);

            console.log("expectedDecay:", expectedDecay);
            console.log("decayedValue:", decayedValue);
            console.log("----------------------------------------------");
            
            // assertApproxEqAbs(
                //     decayedValue,
                //     expectedDecay,
                //     1, // 1% tolerance
                //     "Decay should be proportional to increment/total ratio"
                // );
                
                // Verify the ratio between increment/total equals decayedValue/userValue
                uint256 decayRatio = (decayedValue * 1e18) / userValue;
                
                console.log("total ratio:", ratio);
                console.log("decayRatio:", decayRatio);

                // assertApproxEqAbs(
                //     ratio,
                //     decayRatio,
                //     1,
                //     "Ratio between increment/total should equal decayedValue/userValue"
                // );
                
                // assertLe(decayedValue - expectedDecay, 1, "Decay should be proportional to increment/total ratio");

        }

        //////////// Other Users Accounting ////////////////

        uint256 otherUsersValue = total - userValue;

        // Initialize user's last weight at 0
        uint256 user2LastWeight = 0;
        
        // Calculate the weight delta for the user
        uint256 user2WeightDelta = currentWeight - user2LastWeight;

        uint256 user2DecayedValue = PositionDecay.ScaleByWeightDelta(otherUsersValue, user2WeightDelta);

        console.log("user2DecayedValue:", user2DecayedValue);

        // Assert sum of decayed values equals increment
        console.log("user2DecayedValue + decayedValue:", user2DecayedValue + decayedValue);
        console.log("increment:", increment);
        assertGt(user2DecayedValue + decayedValue, increment, "Sum of decayed values can be greater than increment");

        
        /**
         Logs:
            expectedDecay: 2602347054419317                      
            decayedValue: 2602347054419685
            ----------------------------------------------       
            total ratio: 6121604862441                           
            decayRatio: 6121604862441
            user2DecayedValue: 559241683503294329475235492
            user2DecayedValue + decayedValue: 559241683505896676529655177
            increment: 559241683505896676529655176
         */
    }

    // forge test --match-test testFuzzDecay2PoC -vv
    /**
     counterexample: 
         args=[65711888983981875328876342570773043794 [6.571e37], 28121750387658846337752471388 [2.812e28], 44744369737397 [4.474e13]]]
     */
    function testFuzzDecay2PoC() public {
        uint256 total = 65711888983981875328876342570773043794;
        uint256 increment = 28121750387658846337752471388;
        uint256 userValue = 44744369737397;

        // Constrain inputs to valid ranges
        vm.assume(total > 0);
        vm.assume(total <= type(uint128).max);
        vm.assume(increment <= total);
        vm.assume(userValue <= total); // User value cannot exceed total
        
        // Initialize user's last weight at 0
        uint256 userLastWeight = 0;
        uint256 currentWeight = 0;
        
        // Calculate the new weight increment
        uint256 weightIncrement = PositionDecay.WeightIncrement(increment, total);
        
        // Calculate the weight delta for the user
        currentWeight += weightIncrement;
        uint256 weightDelta = currentWeight - userLastWeight;
        
        // Calculate the expected decayed value
        uint256 decayedValue = PositionDecay.ScaleByWeightDelta(userValue, weightDelta);
        
        // Verify properties:
        
        // 1. If increment is 0, weightIncrement should be 0
        if (increment == 0) {
            assertEq(weightIncrement, 0, "Weight increment should be 0 when increment is 0");
        }
        
        // 2. If weightDelta is 0, decayedValue should be 0
        if (weightDelta == 0) {
            assertEq(decayedValue, 0, "Decayed value should be 0 when weight delta is 0");
        }
        
        // 3. The decayed value should never be greater than the original value
        assertLe(decayedValue, userValue, "Decayed value should never be greater than original value");
        
        // // 4. If increment equals total, the weight should be maximum
        // if (increment == total) {
        //     assertGt(weightIncrement, 0, "Weight increment should be positive when increment equals total");
        // }
        
        // 5. The decay should be proportional to the increment/total ratio
        if (increment > 0 && total > 0) {
            uint256 ratio = (increment * 1e18) / total;
            uint256 expectedDecay = (userValue * ratio) / 1e18;

            vm.assume(ratio > 0);
            vm.assume(expectedDecay > 0);

            console.log("expectedDecay:", expectedDecay);
            console.log("decayedValue:", decayedValue);
            console.log("----------------------------------------------");
            
            // assertApproxEqAbs(
                //     decayedValue,
                //     expectedDecay,
                //     1, // 1% tolerance
                //     "Decay should be proportional to increment/total ratio"
                // );
                
                // Verify the ratio between increment/total equals decayedValue/userValue
                uint256 decayRatio = (decayedValue * 1e18) / userValue;
                
                console.log("total ratio:", ratio);
                console.log("decayRatio:", decayRatio);

                // assertApproxEqAbs(
                //     ratio,
                //     decayRatio,
                //     1,
                //     "Ratio between increment/total should equal decayedValue/userValue"
                // );
                
                // assertLe(decayedValue - expectedDecay, 1, "Decay should be proportional to increment/total ratio");

        }

        //////////// Other Users Accounting ////////////////

        uint256 otherUsersValue = total - userValue;

        // Initialize user's last weight at 0
        uint256 user2LastWeight = 0;
        
        // Calculate the weight delta for the user
        uint256 user2WeightDelta = currentWeight - user2LastWeight;

        uint256 user2DecayedValue = PositionDecay.ScaleByWeightDelta(otherUsersValue, user2WeightDelta);

        console.log("user2DecayedValue:", user2DecayedValue);

        // Assert sum of decayed values equals increment
        console.log("user2DecayedValue + decayedValue:", user2DecayedValue + decayedValue);
        console.log("increment:", increment);
        assertLt(user2DecayedValue + decayedValue, increment, "Sum of decayed values can be less than increment");

        /**
            Logs:
            expectedDecay: 19148
            decayedValue: 19149
            ----------------------------------------------       
            total ratio: 427955288
            decayRatio: 427964459
            user2DecayedValue: 28121750387658846337752452229     
            user2DecayedValue + decayedValue: 28121750387658846337752471378
            increment: 28121750387658846337752471388
         */
    }
}
