// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StakingBBT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract StakingBBTTest is Test {
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
        vm.stopPrank();
    }
    
    // Test initial contract state
    function testInitialState() public {
        assertEq(address(stakingContract.stakingToken()), address(token));
        assertEq(stakingContract.totalStaked(), 0);
        assertEq(stakingContract.rewardRate(), 1e8);
        assertTrue(stakingContract.hasRole(stakingContract.ADMIN_ROLE(), admin));
        assertTrue(stakingContract.hasRole(stakingContract.SELLON_ADMIN_ROLE(), admin));
    }
    
    // Test staking functionality
    function testStake() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();
        
        assertEq(stakingContract.totalStaked(), stakeAmount);
        assertEq(stakingContract.balanceOf(user1), stakeAmount);
        assertEq(token.balanceOf(address(stakingContract)), stakeAmount);
    }
    
    // Test withdrawal functionality
    function testWithdraw() public {
        uint256 stakeAmount = 100 * 10**8;
        
        // First stake some tokens
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        
        // Then withdraw half
        uint256 withdrawAmount = stakeAmount / 2;
        stakingContract.withdraw(withdrawAmount);
        vm.stopPrank();
        
        assertEq(stakingContract.totalStaked(), stakeAmount - withdrawAmount);
        assertEq(stakingContract.balanceOf(user1), stakeAmount - withdrawAmount);
        assertEq(token.balanceOf(address(stakingContract)), stakeAmount - withdrawAmount);
    }
    
    // Test that user can't withdraw more than they staked
    function testWithdrawExceedingBalance() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        
        // Try to withdraw more than staked
        vm.expectRevert("Not enough staked");
        stakingContract.withdraw(stakeAmount + 1);
        vm.stopPrank();
    }
    
    // Test exit functionality
    function testExit() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(user1);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        
        // Wait some time to accrue rewards
        vm.warp(block.timestamp + 30 days);
        
        uint256 expectedReward = stakingContract.earned(user1);
        uint256 balanceBefore = token.balanceOf(user1);
        
        stakingContract.exit();
        vm.stopPrank();
        
        assertEq(stakingContract.balanceOf(user1), 0);
        assertEq(token.balanceOf(user1), balanceBefore + stakeAmount + expectedReward);
    }
}
