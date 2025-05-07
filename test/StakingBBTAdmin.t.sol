// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "../src/StakingBBT.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {MockToken} from "./mocks/MockToken.sol";

// contract StakingBBTAdminTest is Test {
//     StakingBBT public stakingContract;
//     MockToken public token;
//     address public admin = address(1);
//     address public sellonAdmin = address(2);
//     address public user = address(3);
    
//     // Setup the testing environment before each test
//     function setUp() public {
//         vm.startPrank(admin);
//         token = new MockToken();
//         token.mint(admin, 1000000 * 10**8);
//         stakingContract = new StakingBBT(address(token));
        
//         // Set up sellon admin role
//         stakingContract.grantRole(stakingContract.SELLON_ADMIN_ROLE(), sellonAdmin);
        
//         // Fund the accounts
//         token.transfer(sellonAdmin, 10000 * 10**8);
//         token.transfer(user, 1000 * 10**8);
//         token.transfer(address(stakingContract), 100000 * 10**8);
//         vm.stopPrank();
//     }
    
//     // Test admin staking on behalf of user
//     function testStakeByAdmin() public {
//         uint256 stakeAmount = 100 * 10**8;

//         vm.prank(user);
//         token.approve(address(stakingContract), stakeAmount);
        
//         vm.startPrank(sellonAdmin);
//         stakingContract.stake(user, stakeAmount);
//         vm.stopPrank();
        
//         assertEq(stakingContract.totalStaked(), stakeAmount);
//         assertEq(stakingContract.balanceOf(user), stakeAmount);
//     }
    
//     // Test admin withdrawal on behalf of user
//     function testWithdrawByAdmin() public {
//         uint256 stakeAmount = 100 * 10**8;
        
//         vm.startPrank(user);
//         token.approve(address(stakingContract), stakeAmount);
//         vm.stopPrank();

//         // First stake some tokens
//         vm.startPrank(sellonAdmin);
//         stakingContract.stake(user, stakeAmount);
        
//         // Then withdraw half
//         uint256 withdrawAmount = stakeAmount / 2;
//         stakingContract.withdraw(user, withdrawAmount);
//         vm.stopPrank();
        
//         assertEq(stakingContract.totalStaked(), stakeAmount - withdrawAmount);
//         assertEq(stakingContract.balanceOf(user), stakeAmount - withdrawAmount);
//     }
    
//     // Test admin getting rewards on behalf of user
//     function testGetRewardByAdmin() public {
//         uint256 stakeAmount = 100 * 10**8;
        
//         vm.startPrank(user);
//         token.approve(address(stakingContract), stakeAmount);
//         vm.stopPrank();

//         vm.startPrank(sellonAdmin);
//         stakingContract.stake(user, stakeAmount);
//         vm.stopPrank();
        
//         // Wait some time to accrue rewards (120 minutes = 2 hours)
//         vm.warp(block.timestamp + 120 minutes);
        
//         uint256 expectedReward = stakingContract.earned(user);
//         uint256 balanceBefore = token.balanceOf(user);
        
//         vm.prank(sellonAdmin);
//         stakingContract.getReward(user);
        
//         assertEq(token.balanceOf(user), balanceBefore + expectedReward);
//         assertEq(stakingContract.rewards(user), 0);
//     }
    
//     // Test admin exit on behalf of user
//     function testExitByAdmin() public {
//         uint256 stakeAmount = 100 * 10**8;

//         vm.startPrank(user);
//         token.approve(address(stakingContract), stakeAmount);
//         vm.stopPrank();
        
//         vm.startPrank(sellonAdmin);
//         stakingContract.stake(user, stakeAmount);
//         vm.stopPrank();
        
//         // Wait some time to accrue rewards (120 minutes = 2 hours)
//         vm.warp(block.timestamp + 120 minutes);
        
//         uint256 expectedReward = stakingContract.earned(user);
//         uint256 balanceBefore = token.balanceOf(user);
        
//         vm.prank(sellonAdmin);
//         stakingContract.exit(user);
        
//         assertEq(stakingContract.balanceOf(user), 0);
//         assertEq(token.balanceOf(user), balanceBefore + stakeAmount + expectedReward);
//     }
    
//     // Test updating reward rate
//     function testSetAnnualRewardRate() public {
//         uint256 newAnnualRewardRate = 40e8; // 40% annual rate with 8 decimals
        
//         vm.prank(admin);
//         stakingContract.setAnnualRewardRate(newAnnualRewardRate);
        
//         assertEq(stakingContract.annualRewardRate(), newAnnualRewardRate);
//     }

// }
