// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "../src/StakingBBT.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {MockToken} from "./mocks/MockToken.sol";

// contract StakingBBTTest is Test {
//     StakingBBT public stakingContract;
//     MockToken public token;
//     address public admin = address(1);
//     address public sellonAdmin = address(2);
//     address public user1 = address(3);
//     address public user2 = address(4);
    
//     // Setup the testing environment before each test
//     function setUp() public {
//         vm.startPrank(admin);
//         token = new MockToken();
//         token.mint(admin, 1000000 * 10**8);
//         stakingContract = new StakingBBT(address(token));
        
//         // Set up sellon admin role
//         stakingContract.grantRole(stakingContract.SELLON_ADMIN_ROLE(), sellonAdmin);
        
//         // Fund test users
//         token.transfer(user1, 10000 * 10**8);
//         token.transfer(user2, 10000 * 10**8);
//         vm.stopPrank();
//     }
    
//     // Test initial contract state
//     function testInitialState() public {
//         assertEq(address(stakingContract.stakingToken()), address(token));
//         assertEq(stakingContract.totalStaked(), 0);
//         assertEq(stakingContract.annualRewardRate(), 30e8); // 30% annual rate with 8 decimals
//         assertTrue(stakingContract.hasRole(stakingContract.ADMIN_ROLE(), admin));
//         assertTrue(stakingContract.hasRole(stakingContract.SELLON_ADMIN_ROLE(), admin));
//     }
    
//     // Test admin staking on behalf of user
//     function testStake() public {
//         uint256 stakeAmount = 100 * 10**8;
        
//         vm.prank(user1);
//         token.approve(address(stakingContract), stakeAmount);
        
//         vm.prank(sellonAdmin);
//         stakingContract.stake(user1, stakeAmount);
        
//         assertEq(stakingContract.totalStaked(), stakeAmount);
//         assertEq(stakingContract.balanceOf(user1), stakeAmount);
//         assertEq(token.balanceOf(address(stakingContract)), stakeAmount);
//     }
    
//     // Test admin withdrawal on behalf of user
//     function testWithdraw() public {
//         uint256 stakeAmount = 100 * 10**8;
        
//         // First stake some tokens
//         vm.prank(user1);
//         token.approve(address(stakingContract), stakeAmount);
        
//         vm.prank(sellonAdmin);
//         stakingContract.stake(user1, stakeAmount);
        
//         // Then withdraw half
//         uint256 withdrawAmount = stakeAmount / 2;
//         vm.prank(sellonAdmin);
//         stakingContract.withdraw(user1, withdrawAmount);
        
//         assertEq(stakingContract.totalStaked(), stakeAmount - withdrawAmount);
//         assertEq(stakingContract.balanceOf(user1), stakeAmount - withdrawAmount);
//         assertEq(token.balanceOf(user1), 10000 * 10**8 - stakeAmount + withdrawAmount);
//     }
    
//     // Test that withdrawal reverts for insufficient balance
//     function testWithdrawExceedingBalance() public {
//         uint256 stakeAmount = 100 * 10**8;
        
//         vm.prank(user1);
//         token.approve(address(stakingContract), stakeAmount);
        
//         vm.prank(sellonAdmin);
//         stakingContract.stake(user1, stakeAmount);
        
//         // Try to withdraw more than staked
//         vm.expectRevert("Not enough staked");
//         vm.prank(sellonAdmin);
//         stakingContract.withdraw(user1, stakeAmount + 1);
//     }
    
//     // Test admin exit on behalf of user
//     function testExit() public {
//         uint256 stakeAmount = 100 * 10**8;
        
//         vm.prank(user1);
//         token.approve(address(stakingContract), stakeAmount);
        
//         vm.prank(sellonAdmin);
//         stakingContract.stake(user1, stakeAmount);
        
//         // Wait some time to accrue rewards (30 minutes)
//         vm.warp(block.timestamp + 30 minutes);
        
//         uint256 expectedReward = stakingContract.earned(user1);
//         uint256 balanceBefore = token.balanceOf(user1);
        
//         vm.prank(sellonAdmin);
//         stakingContract.exit(user1);
        
//         assertEq(stakingContract.balanceOf(user1), 0);
//         assertEq(token.balanceOf(user1), balanceBefore + stakeAmount + expectedReward);
//     }
// }
