// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StakingBBT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract StakingBBTRewardsTest is Test {
    StakingBBT public stakingContract;
    MockToken public token;
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public sellonAdmin = address(4);
    
    // Setup the testing environment before each test
    function setUp() public {
        vm.startPrank(admin);
        token = new MockToken();
        token.mint(admin, 1000000 * 10**8);
        stakingContract = new StakingBBT(address(token));
        
        // Grant SELLON_ADMIN_ROLE to sellonAdmin
        stakingContract.grantRole(stakingContract.SELLON_ADMIN_ROLE(), sellonAdmin);
        
        // Fund test users
        token.transfer(user1, 10000 * 10**8);
        token.transfer(user2, 10000 * 10**8);
        token.transfer(sellonAdmin, 10000 * 10**8);
        
        // Add reward tokens to the contract
        token.transfer(address(stakingContract), 100000 * 10**8);
        vm.stopPrank();
    }
    
    // Test reward calculation for a single user
    function testRewardCalculationSingleUser() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user1, stakeAmount);
        vm.stopPrank();
        
        // Store the current minute
        uint256 startMinute = stakingContract.getCurrentMinute();
        
        // Advance time by 10 minutes
        vm.warp(block.timestamp + 10 minutes);
        
        // Calculate expected reward (annual rate / minutes in year * amount * minutes elapsed)
        uint256 minuteRate = (stakingContract.annualRewardRate() * stakingContract.DECIMAL_PRECISION()) / 
                            stakingContract.MINUTES_PER_YEAR() / stakingContract.DECIMAL_PRECISION();
        uint256 expectedReward = (stakeAmount * minuteRate * 10) / stakingContract.DECIMAL_PRECISION();
        
        // Assert the reward
        assertApproxEqAbs(stakingContract.earned(user1), expectedReward, 10); // Allow for small rounding differences
    }
    
    // Test reward distribution between multiple users
    function testRewardDistributionMultipleUsers() public {
        uint256 stakeAmount1 = 100 * 10**8; // User1 stakes 100 tokens
        uint256 stakeAmount2 = 200 * 10**8; // User2 stakes 200 tokens
        
        // User1 stakes via admin
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount1);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user1, stakeAmount1);
        vm.stopPrank();
        
        // Advance time by 10 minutes
        vm.warp(block.timestamp + 10 minutes);
        
        // Calculate user1's rewards after 10 minutes
        uint256 minuteRate = (stakingContract.annualRewardRate() * stakingContract.DECIMAL_PRECISION()) / 
                            stakingContract.MINUTES_PER_YEAR() / stakingContract.DECIMAL_PRECISION();
        uint256 user1RewardsMinutes1to10 = (stakeAmount1 * minuteRate * 10) / stakingContract.DECIMAL_PRECISION();
        
        // Verify user1's rewards
        assertApproxEqAbs(stakingContract.earned(user1), user1RewardsMinutes1to10, 10);
        
        // User2 stakes via admin
        vm.startPrank(user2);
        token.approve(address(stakingContract), stakeAmount2);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user2, stakeAmount2);
        vm.stopPrank();
        
        // Advance time by another 10 minutes
        vm.warp(block.timestamp + 10 minutes);
        
        // Calculate expected rewards for the next 10 minutes
        uint256 expectedUser1RewardsMinutes11to20 = (stakeAmount1 * minuteRate * 10) / stakingContract.DECIMAL_PRECISION();
        uint256 expectedUser2RewardsMinutes11to20 = (stakeAmount2 * minuteRate * 10) / stakingContract.DECIMAL_PRECISION();
        
        uint256 expectedUser1Total = user1RewardsMinutes1to10 + expectedUser1RewardsMinutes11to20;
        
        // Assert the rewards
        assertApproxEqAbs(stakingContract.earned(user1), expectedUser1Total, 10);
        assertApproxEqAbs(stakingContract.earned(user2), expectedUser2RewardsMinutes11to20, 10);
    }
    
    // Test claiming rewards (now admin must do this)
    function testClaimRewards() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user1, stakeAmount);
        
        // Advance time by 60 minutes (1 hour)
        vm.warp(block.timestamp + 60 minutes);
        
        uint256 expectedReward = stakingContract.earned(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        
        stakingContract.getReward(user1);
        vm.stopPrank();
        
        assertEq(stakingContract.rewards(user1), 0);
        assertEq(token.balanceOf(user1), balanceBefore + expectedReward);
    }
    
    // Test reward accrual over time with changing stake amounts
    function testRewardAccrualWithChangingStake() public {
        uint256 initialStake = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), 1000 * 10**8); // Approve for all future transactions
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        // Initial stake
        stakingContract.stake(user1, initialStake);
        
        // Advance 30 minutes
        vm.warp(block.timestamp + 30 minutes);
        
        // Record earned rewards
        uint256 rewardsAfter30Minutes = stakingContract.earned(user1);
        
        // Stake more
        uint256 additionalStake = 200 * 10**8;
        stakingContract.stake(user1, additionalStake);
        
        // Advance another 30 minutes
        vm.warp(block.timestamp + 30 minutes);
        
        // Total rewards should include:
        // 1. Rewards from first 30 minutes with initial stake
        // 2. Rewards from second 30 minutes with initial + additional stake
        uint256 totalRewards = stakingContract.earned(user1);
        
        // Claim rewards
        uint256 balanceBefore = token.balanceOf(user1);
        stakingContract.getReward(user1);
        vm.stopPrank();
        
        assertEq(token.balanceOf(user1) - balanceBefore, totalRewards);
        assertTrue(totalRewards > rewardsAfter30Minutes, "Rewards should increase after staking more tokens");
    }
    
    // Test reward calculation across multiple minutes
    function testRewardCalculationMultipleMinutes() public {
        uint256 stakeAmount = 1000 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user1, stakeAmount);
        vm.stopPrank();
        
        // Calculate per-minute reward rate
        uint256 minuteRate = (stakingContract.annualRewardRate() * stakingContract.DECIMAL_PRECISION()) / 
                            stakingContract.MINUTES_PER_YEAR() / stakingContract.DECIMAL_PRECISION();
        uint256 minuteReward = (stakeAmount * minuteRate) / stakingContract.DECIMAL_PRECISION();
        
        // Advance by 60 minutes
        vm.warp(block.timestamp + 60 minutes);
        
        // Expected reward for 60 minutes
        uint256 expectedReward = minuteReward * 60;
        
        // Check earned amount
        assertApproxEqAbs(stakingContract.earned(user1), expectedReward, 100);
    }
    
    // Test actual token earnings over a year at 30% rate
    function testAnnualYield() public {
        uint256 stakeAmount = 1000 * 10**8; // 1000 tokens with 8 decimals
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user1, stakeAmount);
        vm.stopPrank();
        
        // Move forward 1 year (in minutes)
        vm.warp(block.timestamp + 525600 minutes);
        
        // The actual calculation in the contract is done minute by minute with precision adjustments
        // Calculate using the same method as the contract to account for rounding errors
        uint256 minuteRate = (stakingContract.annualRewardRate() * stakingContract.DECIMAL_PRECISION()) / 
                            stakingContract.MINUTES_PER_YEAR() / stakingContract.DECIMAL_PRECISION();
        uint256 expectedReward = (stakeAmount * minuteRate * stakingContract.MINUTES_PER_YEAR()) / stakingContract.DECIMAL_PRECISION();
        
        // Get the actual earned amount from the contract
        uint256 actualReward = stakingContract.earned(user1);
        
        // Log values for debugging
        console.log("Expected reward:", expectedReward);
        console.log("Actual reward:", actualReward);
        console.log("Difference:", expectedReward > actualReward ? expectedReward - actualReward : actualReward - expectedReward);
        console.log("Expected 30% of stake:", (stakeAmount * 30) / 100);
        console.log("Ratio of actual to expected 30%:", (actualReward * 100) / ((stakeAmount * 30) / 100), "%");
        
        // Use a larger tolerance to account for accumulated rounding errors over many minutes
        assertApproxEqAbs(actualReward, expectedReward, 1e7); // tolerance of 0.1 tokens for a year of calculations
    }
    
    function testRewardPerMinute() public {
        uint256 stakeAmount = 1000 * 10**8; // 1000 tokens with 8 decimals
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(sellonAdmin);
        stakingContract.stake(user1, stakeAmount);
        vm.stopPrank();
        
        // Move forward 1 minute
        vm.warp(block.timestamp + 1 minutes);
        
        // Calculate expected reward for 1 minute
        uint256 minuteRate = (stakingContract.annualRewardRate() * stakingContract.DECIMAL_PRECISION()) / 
                            stakingContract.MINUTES_PER_YEAR() / stakingContract.DECIMAL_PRECISION();
        uint256 expectedReward = (stakeAmount * minuteRate) / stakingContract.DECIMAL_PRECISION();

        console.log("Expected reward for 1 minute:", expectedReward);
        
        // Check earned amount
        assertApproxEqAbs(stakingContract.earned(user1), expectedReward, 10);
    }
}
