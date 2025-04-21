// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StakingBBT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract StakingBBTAdminTest is Test {
    StakingBBT public stakingContract;
    MockToken public token;
    address public admin = address(1);
    address public sellonAdmin = address(2);
    address public user = address(3);
    
    // Setup the testing environment before each test
    function setUp() public {
        vm.startPrank(admin);
        token = new MockToken();
        token.mint(admin, 1000000 * 10**8);
        stakingContract = new StakingBBT(address(token));
        
        // Set up sellon admin role
        stakingContract.grantRole(stakingContract.SELLON_ADMIN_ROLE(), sellonAdmin);
        
        // Fund the accounts
        token.transfer(sellonAdmin, 10000 * 10**8);
        token.transfer(user, 1000 * 10**8);
        vm.stopPrank();
    }
    
    // Test admin staking on behalf of user
    function testStakeByAdmin() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(sellonAdmin);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stakeByAdmin(user, stakeAmount);
        vm.stopPrank();
        
        assertEq(stakingContract.totalStaked(), stakeAmount);
        assertEq(stakingContract.balanceOf(user), stakeAmount);
        assertEq(token.balanceOf(address(stakingContract)), stakeAmount);
    }
    
    // Test admin withdrawal on behalf of user
    function testWithdrawByAdmin() public {
        uint256 stakeAmount = 100 * 10**8;
        
        // First stake some tokens
        vm.startPrank(sellonAdmin);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stakeByAdmin(user, stakeAmount);
        
        // Then withdraw half
        uint256 withdrawAmount = stakeAmount / 2;
        stakingContract.withdrawByAdmin(user, withdrawAmount);
        vm.stopPrank();
        
        assertEq(stakingContract.totalStaked(), stakeAmount - withdrawAmount);
        assertEq(stakingContract.balanceOf(user), stakeAmount - withdrawAmount);
        assertEq(token.balanceOf(user), 1000 * 10**8 + withdrawAmount);
    }
    
    // Test admin getting rewards on behalf of user
    function testGetRewardByAdmin() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(sellonAdmin);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stakeByAdmin(user, stakeAmount);
        vm.stopPrank();
        
        // Wait some time to accrue rewards
        vm.warp(block.timestamp + 30 days);
        
        uint256 expectedReward = stakingContract.earned(user);
        uint256 balanceBefore = token.balanceOf(user);
        
        vm.prank(sellonAdmin);
        stakingContract.getRewardByAdmin(user);
        
        assertEq(token.balanceOf(user), balanceBefore + expectedReward);
        assertEq(stakingContract.rewards(user), 0);
    }
    
    // Test admin exit on behalf of user
    function testExitByAdmin() public {
        uint256 stakeAmount = 100 * 10**8;
        
        vm.startPrank(sellonAdmin);
        token.approve(address(stakingContract), stakeAmount);
        stakingContract.stakeByAdmin(user, stakeAmount);
        vm.stopPrank();
        
        // Wait some time to accrue rewards
        vm.warp(block.timestamp + 30 days);
        
        uint256 expectedReward = stakingContract.earned(user);
        uint256 balanceBefore = token.balanceOf(user);
        
        vm.prank(sellonAdmin);
        stakingContract.exitByAdmin(user);
        
        assertEq(stakingContract.balanceOf(user), 0);
        assertEq(token.balanceOf(user), balanceBefore + stakeAmount + expectedReward);
    }
    
    // Test updating reward rate
    function testSetRewardRate() public {
        uint256 newRewardRate = 2e8;
        
        vm.prank(admin);
        stakingContract.setRewardRate(newRewardRate);
        
        assertEq(stakingContract.rewardRate(), newRewardRate);
    }
    
    // Test adding reward tokens
    function testAddRewardTokens() public {
        uint256 additionalRewards = 1000 * 10**8;
        
        vm.startPrank(admin);
        token.approve(address(stakingContract), additionalRewards);
        stakingContract.addRewardTokens(additionalRewards);
        vm.stopPrank();
        
        assertEq(token.balanceOf(address(stakingContract)), additionalRewards);
    }
}
