// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is Test {
    // Counter public counter;

    // function setUp() public {
    //     counter = new Counter();
    //     counter.setNumber(0);
    // }

    // function test_Increment() public {
    //     counter.increment();
    //     assertEq(counter.number(), 1);
    // }
    uint256 constant BPS = 10_000;
    uint256 constant FIXED_POINT_SCALAR = 1e18;
    uint256 constant TARGET_COLLATERALIZATION = 15e17; // 150%
    uint256 constant LIQUIDATOR_FEE = 1000; // 10%

    // forge test --match-test testFuzzLiquidationRatio --fuzz-runs 1000000 -vv
    function testFuzzLiquidationRatio(uint256 initialCollateral, uint256 debt) public {
        vm.assume(initialCollateral > debt);
        vm.assume(initialCollateral < 100_000e18);
        vm.assume(debt < 100_000e18);
        vm.assume(initialCollateral > 10e18);
        vm.assume(debt > 10e18);

        (uint256 grossCollateralToSeize, uint256 debtToBurn, uint256 fee) = calculateLiquidation(
            initialCollateral, 
            debt, 
            TARGET_COLLATERALIZATION, 
            LIQUIDATOR_FEE
        );

        if (grossCollateralToSeize == debtToBurn && fee == 0) {
            assertTrue(true);
        }

        uint256 finalCollateral = initialCollateral - grossCollateralToSeize;
        uint256 finalDebt = debt - debtToBurn;

        uint256 finalRatio = (finalCollateral * FIXED_POINT_SCALAR) / finalDebt;

        console.log("initialCollateral:", initialCollateral);
        console.log("debt:", debt);
        console.log("finalCollateral:", finalCollateral);
        console.log("finalDebt:", finalDebt);
        console.log("finalRatio:", finalRatio);
        console.log("TARGET_COLLATERALIZATION:", TARGET_COLLATERALIZATION);
        assertTrue(finalRatio >= TARGET_COLLATERALIZATION);
    }

    // forge test --match-test testPoCLiquidationRatio --fuzz-runs 1000000 -vv
    function testPoCLiquidationRatio() public {
        uint256 initialCollateral = 14345114475101827901914;
        uint256 debt = 10219179616359521436103;

        (uint256 grossCollateralToSeize, uint256 debtToBurn, uint256 fee) = calculateLiquidation(
            initialCollateral, 
            debt, 
            TARGET_COLLATERALIZATION, 
            LIQUIDATOR_FEE
        );


        if (grossCollateralToSeize == debtToBurn && fee == 0) {
            assertTrue(true);
        }

        uint256 finalCollateral = initialCollateral - grossCollateralToSeize;
        uint256 finalDebt = debt - debtToBurn;

        uint256 finalRatio = (finalCollateral * FIXED_POINT_SCALAR) / finalDebt;

        console.log("initialCollateral:", initialCollateral);
        console.log("debt:", debt);
        console.log("finalCollateral:", finalCollateral);
        console.log("finalDebt:", finalDebt);
        console.log("finalRatio:", finalRatio);
        console.log("TARGET_COLLATERALIZATION:", TARGET_COLLATERALIZATION);
        assertTrue(finalRatio >= TARGET_COLLATERALIZATION);

        /**
         Logs:
            initialCollateral: 14345114475101827901914
            debt: 10219179616359521436103                        
            finalCollateral: 11140024118604227457691             
            finalDebt: 7426682745736151638461                    
            finalRatio: 1499999999999999999                      
            TARGET_COLLATERALIZATION: 1500000000000000000 
        */
    }



    function calculateLiquidation(
        uint256 collateral,
        uint256 debt,
        uint256 targetCollateralization,
        // uint256 alchemistCurrentCollateralization,
        // uint256 alchemistMinimumCollateralization,
        uint256 feeBps
    ) internal pure returns (uint256 grossCollateralToSeize, uint256 debtToBurn, uint256 fee) {
        if (debt >= collateral) {
            // fully liquidate bad debt
            return (debt, debt, 0);
        }

        // Note: This is not needed for POC
        // if (alchemistCurrentCollateralization < alchemistMinimumCollateralization) {
        //     // fully liquidate debt in high ltv global environment
        //     return (debt, debt, 0);
        // }

        // 1) fee is taken from surplus = collateral - debt
        uint256 surplus = collateral > debt ? collateral - debt : 0;
        fee = (surplus * feeBps) / BPS;

        // 2) collateral remaining for margin‐restore calc
        uint256 adjCollat = collateral - fee;

        // 3) compute m*d  (both plain units)
        uint256 md = (targetCollateralization * debt) / FIXED_POINT_SCALAR;
        // Note: Test Passes with this version of md 
        // uint256 md = ((targetCollateralization + 1) * debt) / FIXED_POINT_SCALAR;

        // 4) if md <= adjCollat, nothing to liquidate
        if (md <= adjCollat) {
            return (0, 0, fee);
        }

        // 5) numerator = md - adjCollat
        uint256 num = md - adjCollat;

        // 6) denom = m - 1  =>  (targetCollateralization - FIXED_POINT_SCALAR)/FIXED_POINT_SCALAR
        uint256 denom = targetCollateralization - FIXED_POINT_SCALAR;

        // 7) debtToBurn = (num * FIXED_POINT_SCALAR) / denom
        debtToBurn = (num * FIXED_POINT_SCALAR) / denom;

        // 8) gross collateral seize = net + fee
        grossCollateralToSeize = debtToBurn + fee;
    }
}
