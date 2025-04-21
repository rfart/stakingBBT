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
    
    // Setup the testing environment before each test
    function setUp() public {
        vm.startPrank(admin);
        token = new MockToken();
        token.mint(admin, 1000000 * 10**8);
        stakingContract = new StakingBBT(address(token));
        
        // Fund test users
        token.transfer(user1, 10000 * 10**8);
        token.transfer(user2, 10000 * 10**8);
        
        // Add reward tokens to the contract
        token.approve(address(stakingContract), 100000 * 10**8);
        stakingContract.addRewardTokens(100000 * 10**8);
        vm.stopPrank();
    }
    
    // Test reward calculation for a single user
    function testRewardCalculationSingleUser() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();
        
        // Advance time
        uint256 duration = 1 days;
        vm.warp(block.timestamp + duration);
        
        // Calculate expected reward
        uint256 expectedReward = (duration * stakingContract.rewardRate() * 1e8) / 1e8;
        
        // Assert the reward
        assertApproxEqAbs(stakingContract.earned(user1), expectedReward, 1); // Allow for small rounding differences
    }
    
    // Test reward distribution between multiple users
    function testRewardDistributionMultipleUsers() public {
        uint256 stakeAmount1 = 100 * 10**8; // User1 stakes 100 tokens
        uint256 stakeAmount2 = 200 * 10**8; // User2 stakes 200 tokens
        
        // User1 stakes
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount1);
        stakingContract.stake(stakeAmount1);
        vm.stopPrank();
        
        // Advance time
        vm.warp(block.timestamp + 1 days);
        
        // User2 stakes
        vm.startPrank(user2);
        token.approve(address(stakingContract), stakeAmount2);
        stakingContract.stake(stakeAmount2);
        vm.stopPrank();
        
        // User1 should have rewards from the first day
        uint256 user1RewardsDay1 = stakingContract.earned(user1);
        
        // Advance time again
        vm.warp(block.timestamp + 1 days);
        
        // Calculate expected rewards
        // User1 gets 100% of rewards for day1, and 1/3 of rewards for day2
        // User2 gets 2/3 of rewards for day2
        uint256 dailyReward = 24 * 60 * 60 * stakingContract.rewardRate();
        
        uint256 expectedUser1RewardsDay2 = (dailyReward * stakeAmount1) / (stakeAmount1 + stakeAmount2);
        uint256 expectedUser2RewardsDay2 = (dailyReward * stakeAmount2) / (stakeAmount1 + stakeAmount2);
        
        uint256 expectedUser1Total = user1RewardsDay1 + expectedUser1RewardsDay2;
        
        // Assert the rewards with some tolerance for rounding
        assertApproxEqAbs(stakingContract.earned(user1), expectedUser1Total, 10);
        assertApproxEqAbs(stakingContract.earned(user2), expectedUser2RewardsDay2, 10);
    }
    
    // Test claiming rewards
    function testClaimRewards() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        
        // Advance time
        vm.warp(block.timestamp + 30 days);
        
        uint256 expectedReward = stakingContract.earned(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        
        stakingContract.getReward();
        vm.stopPrank();
        
        assertEq(stakingContract.rewards(user1), 0);
        assertEq(token.balanceOf(user1), balanceBefore + expectedReward);
    }
    
    // Test reward accrual over time with changing stake amounts
    function testRewardAccrualWithChangingStake() public {
        uint256 initialStake = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), 1000 * 10**8); // Approve for all future transactions
        
        // Initial stake
        stakingContract.stake(initialStake);
        
        // Advance 10 days
        vm.warp(block.timestamp + 10 days);
        
        // Record earned rewards
        uint256 rewardsAfter10Days = stakingContract.earned(user1);
        
        // Stake more
        uint256 additionalStake = 200 * 10**8;
        stakingContract.stake(additionalStake);
        
        // Advance another 10 days
        vm.warp(block.timestamp + 10 days);
        
        // Total rewards should include:
        // 1. Rewards from first 10 days with initial stake
        // 2. Rewards from second 10 days with initial + additional stake
        uint256 totalRewards = stakingContract.earned(user1);
        
        // Claim rewards
        uint256 balanceBefore = token.balanceOf(user1);
        stakingContract.getReward();
        vm.stopPrank();
        
        assertEq(token.balanceOf(user1) - balanceBefore, totalRewards);
        assertTrue(totalRewards > rewardsAfter10Days, "Rewards should increase after staking more tokens");
    }
}
