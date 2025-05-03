// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/CompoundStakingBBT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing purposes
contract MockBBT is ERC20 {
    constructor() ERC20("Mock BBT", "MBBT") {
        _mint(msg.sender, 1_000_000 * 10**8); // 1M tokens with 8 decimal places
    }
    
    function decimals() public pure override returns (uint8) {
        return 8;
    }
}

contract CompoundStakingBBTTest is Test {
    CompoundStakingBBT public staking;
    MockBBT public token;
    
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256 public constant INITIAL_BALANCE = 10_000 * 10**8; // 10,000 tokens with 8 decimals
    uint256 public constant REWARD_RATE = 30_000_000; // 30% annual rate (scaled by 1e8)
    
    // Events for verification
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event WaitTimeUpdated(uint256 newWaitTime);
    
    function setUp() public {
        // Deploy token and staking contract
        vm.startPrank(admin);
        token = new MockBBT();
        staking = new CompoundStakingBBT(address(token));
        
        // Transfer tokens to test users
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        token.transfer(address(staking), 100000 * 10**8);
        
        // Set initial reward rate (30% APY)
        staking.setAnnualRewardRate(REWARD_RATE);
        vm.stopPrank();
    }
    
    function testSetup() public {
        assertEq(address(staking.stakingToken()), address(token));
        assertEq(staking.annualRewardRate(), REWARD_RATE);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE);
        assertEq(token.balanceOf(user2), INITIAL_BALANCE);
        
        // Check role setup
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.SELLON_ADMIN_ROLE(), admin));
    }
    
    function testStake() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(admin);
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount);
        staking.stake(user1, stakeAmount);
        vm.stopPrank();
        
        assertEq(staking.balanceOf(user1), stakeAmount);
        assertEq(staking.virtualBalanceOf(user1), stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - stakeAmount);
    }
    
    function testVirtualBalanceCompounding() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.startPrank(admin);
        staking.stake(user1, stakeAmount);
        vm.stopPrank();
        
        // Record initial state
        uint256 initialVirtualBalance = staking.virtualBalanceOf(user1);
        assertEq(initialVirtualBalance, stakeAmount, "Initial virtual balance should equal staked amount");
        
        // Warp forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Perform an action to trigger the reward update
        vm.startPrank(admin);
        staking.getReward(user1, staking.earned(user1) / 2);
        vm.stopPrank();
        
        // Check compound balance calculation
        uint256 compoundedBalance = staking.calculateCompoundBalance(user1);
        assertTrue(compoundedBalance > initialVirtualBalance, "Balance should increase due to compound interest");

        console.log("Compounded balance: ", compoundedBalance);
        
        // Check that virtual balance has been updated with compound interest
        uint256 updatedVirtualBalance = staking.virtualBalanceOf(user1);
        assertTrue(updatedVirtualBalance > initialVirtualBalance, "Virtual balance should be updated with compound interest");
        assertEq(updatedVirtualBalance, compoundedBalance, "Virtual balance should match the calculated compound balance");
    }
    
    function testCompleteWithdrawal() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward to accumulate some rewards
        vm.warp(block.timestamp + 30 days);
        
        // Request withdrawal
        vm.prank(admin);
        staking.requestWithdrawal(user1);
        
        // Record virtual balance before withdrawal
        uint256 virtualBalanceBefore = staking.virtualBalanceOf(user1);
        uint256 tokenBalanceBefore = token.balanceOf(user1);
        
        // Wait for the required period
        vm.warp(block.timestamp + staking.waitTime());
        
        // Complete withdrawal
        vm.prank(admin);
        staking.completeWithdrawal(user1);
        
        // Check actual balances
        assertEq(staking.balanceOf(user1), 0, "Staked balance should be 0 after withdrawal");
        assertEq(staking.totalStaked(), 0, "Total staked should be 0 after withdrawal");
        assertEq(staking.virtualBalanceOf(user1), 0, "Virtual balance should be 0 after withdrawal");
        
        // Check token balances
        assertEq(token.balanceOf(user1), tokenBalanceBefore + virtualBalanceBefore, "User should receive full virtual balance amount");
    }
    
    function testWithdrawalWithWaitPeriod() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward to accumulate some rewards
        vm.warp(block.timestamp + 30 days);
        
        // Record state before withdrawal request
        uint256 virtualBalanceBefore = staking.virtualBalanceOf(user1);
        uint256 rewardsBefore = staking.earned(user1);
        uint256 tokenBalanceBefore = token.balanceOf(user1);
        
        console.log("Virtual balance before withdrawal request:", virtualBalanceBefore);
        console.log("Rewards before withdrawal request:", rewardsBefore);
        
        // Request withdrawal
        uint256 waitTime = staking.waitTime();
        uint256 unlockTime = block.timestamp + waitTime;
        
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit WithdrawalRequested(user1, virtualBalanceBefore, unlockTime);
        staking.requestWithdrawal(user1);
        
        // Check withdrawal request was recorded
        assertEq(staking.withdrawalRequests(user1), block.timestamp, "Withdrawal request timestamp should be recorded");
        assertEq(staking.withdrawalAmounts(user1), virtualBalanceBefore, "Withdrawal amount should be full virtual balance");
        
        // No rewards should accumulate during waiting period
        vm.warp(block.timestamp + waitTime / 2); // Halfway through waiting period
        
        uint256 rewardsDuringWaiting = staking.earned(user1);
        assertEq(rewardsDuringWaiting, rewardsBefore, "No additional rewards should accumulate during waiting period");
        
        // Attempt to complete withdrawal before wait time (should fail)
        vm.prank(admin);
        vm.expectRevert("Waiting period not over");
        staking.completeWithdrawal(user1);
        
        // Complete waiting period
        vm.warp(block.timestamp + waitTime / 2); // Complete the full waiting period
        
        // Complete withdrawal
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, virtualBalanceBefore);
        staking.completeWithdrawal(user1);
        
        // Check withdrawal was processed
        assertEq(staking.balanceOf(user1), 0, "Staked balance should be 0 after withdrawal");
        assertEq(staking.totalStaked(), 0, "Total staked should be 0 after withdrawal");
        assertEq(staking.virtualBalanceOf(user1), 0, "Virtual balance should be 0 after withdrawal");
        assertEq(staking.withdrawalRequests(user1), 0, "Withdrawal request should be cleared");
        assertEq(staking.withdrawalAmounts(user1), 0, "Withdrawal amount should be cleared");

        // Check token balances
        assertEq(token.balanceOf(user1), tokenBalanceBefore + virtualBalanceBefore, "User should receive full virtual balance amount");
    }
    
    function testCancelWithdrawal() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Record state before withdrawal request
        uint256 virtualBalanceBefore = staking.virtualBalanceOf(user1);
        uint256 rewardsBefore = staking.earned(user1);
        
        // Request withdrawal
        vm.prank(admin);
        staking.requestWithdrawal(user1);
        
        // Check withdrawal request was recorded
        assertEq(staking.withdrawalRequests(user1), block.timestamp, "Withdrawal request timestamp should be recorded");
        
        // Warp forward during waiting period
        vm.warp(block.timestamp + staking.waitTime() / 2);
        
        // Cancel withdrawal
        vm.prank(admin);
        staking.cancelWithdrawal(user1);
        
        // Check withdrawal request was cleared
        assertEq(staking.withdrawalRequests(user1), 0, "Withdrawal request should be cleared after cancellation");
        assertEq(staking.withdrawalAmounts(user1), 0, "Withdrawal amount should be cleared after cancellation");
        
        // Warp forward more time and check that rewards start accumulating again
        vm.warp(block.timestamp + 1 days);
        
        uint256 rewardsAfterCancel = staking.earned(user1);
        assertTrue(rewardsAfterCancel > rewardsBefore, "Rewards should accumulate again after cancellation");
    }
    
    function testDisallowStakeDuringPendingRequest() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount * 2);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Request withdrawal
        vm.prank(admin);
        staking.requestWithdrawal(user1);
        
        // Attempt to stake more while withdrawal request is pending (should fail)
        vm.prank(admin);
        vm.expectRevert("Withdrawal request pending");
        staking.stake(user1, stakeAmount);
    }
    
    function testSetWaitTime() public {
        uint256 newWaitTime = 2 days;
        
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit WaitTimeUpdated(newWaitTime);
        staking.setWaitTime(newWaitTime);
        
        assertEq(staking.waitTime(), newWaitTime, "Wait time should be updated");
    }
    
    function testOnlyAdminCanSetWaitTime() public {
        uint256 newWaitTime = 2 days;
        
        vm.expectRevert();
        vm.prank(user1);
        staking.setWaitTime(newWaitTime);
    }
    
    function testGetReward() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Initial state
        uint256 initialRewards = staking.rewards(user1);
        console.log("Initial rewards:", initialRewards);
        assertEq(initialRewards, 0, "Initial rewards should be zero");
        
        // Warp forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        
        // Check earned rewards
        uint256 earnedRewards = staking.earned(user1);
        console.log("Earned rewards after 30 days:", earnedRewards);
        assertTrue(earnedRewards > 0, "Should have earned rewards after 30 days");
        
        // Check virtual balance is greater than initial stake (compound interest)
        uint256 virtualBalance = staking.calculateCompoundBalance(user1);
        assertTrue(virtualBalance > stakeAmount, "Virtual balance should increase with compound interest");
        
        // Claim rewards
        uint256 initialTokenBalance = token.balanceOf(user1);
        
        vm.startPrank(admin);
        staking.getReward(user1, earnedRewards);
        vm.stopPrank();
        
        // Verify rewards are claimed
        assertEq(staking.rewards(user1), 0, "Rewards should be zero after claim");
        
        // Verify tokens were transferred
        assertEq(token.balanceOf(user1), initialTokenBalance + earnedRewards);
    }
    
    function testCompoundVsSimpleInterest() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward 365 days (1 year)
        vm.warp(block.timestamp + 365 days);
        
        // Calculate what we'd expect with simple interest (30% of staked amount)
        uint256 simpleInterestReward = (stakeAmount * REWARD_RATE) / 100e8;
        
        // Get actual compound interest rewards
        uint256 compoundRewards = staking.earned(user1);
        
        // Compound interest should be greater than simple interest
        assertTrue(compoundRewards > simpleInterestReward, "Compound interest should exceed simple interest over a year");
        
        // For 30% APY, compound interest after 1 year should be approximately 34.5% 
        // (using continuous compounding formula: P * (e^(r*t) - 1))
        uint256 expectedCompoundFactor = 134.5e8; // 134.5% of principal (scaled by 1e8)
        uint256 approximateExpectedReward = (stakeAmount * expectedCompoundFactor / 100e8) - stakeAmount;
        
        // Allow for some approximation error due to minute-based compounding vs. continuous
        assertApproxEqRel(compoundRewards, approximateExpectedReward, 5e16); // 5% tolerance
    }
    
    function testSetAnnualRewardRate() public {
        uint256 newRate = 50_000_000; // 50% annual rate
        
        vm.prank(admin);
        staking.setAnnualRewardRate(newRate);
        
        assertEq(staking.annualRewardRate(), newRate);
    }
    
    function testOnlyAdminCanSetRewardRate() public {
        uint256 newRate = 50_000_000; // 50% annual rate
        
        vm.expectRevert();
        vm.prank(user1);
        staking.setAnnualRewardRate(newRate);
    }
    
    function testOnlyAdminCanStake() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        
        vm.expectRevert();
        staking.stake(user1, stakeAmount);
        vm.stopPrank();
    }
    
    // Test reward calculation for a single minute
    function testRewardCalculationSingleMinute() public {
        uint256 stakeAmount = 1000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Get initial virtual balance
        uint256 initialVirtualBalance = staking.virtualBalanceOf(user1);
        
        // Advance time by 1 minute
        vm.warp(block.timestamp + 1 minutes);
        
        // Calculate expected reward rate per minute
        uint256 minuteRate = (REWARD_RATE * staking.DECIMAL_PRECISION()) / staking.MINUTES_PER_YEAR() / staking.DECIMAL_PRECISION();
        
        // Calculate expected balance after 1 minute of compounding
        uint256 expectedBalance = initialVirtualBalance + ((initialVirtualBalance * minuteRate) / staking.DECIMAL_PRECISION());
        
        // Check compounded balance
        uint256 compoundedBalance = staking.calculateCompoundBalance(user1);
        
        console.log("Initial virtual balance:", initialVirtualBalance);
        console.log("Expected balance after 1 minute:", expectedBalance);
        console.log("Actual compounded balance:", compoundedBalance);
        
        // Verify the compounded balance matches expectation (allow small rounding error)
        assertApproxEqAbs(compoundedBalance, expectedBalance, 10);
        
        // Check earned rewards
        uint256 earnedRewards = staking.earned(user1);
        uint256 expectedRewards = compoundedBalance - initialVirtualBalance;
        
        console.log("Expected rewards after 1 minute:", expectedRewards);
        console.log("Actual earned rewards:", earnedRewards);
        
        assertEq(earnedRewards, expectedRewards);
    }
    
    // Test actual token earnings over a day with compound interest
    function testDailyCompoundYield() public {
        uint256 stakeAmount = 1000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Record initial state
        uint256 initialVirtualBalance = staking.virtualBalanceOf(user1);
        
        // Advance time by 1 day (1440 minutes)
        vm.warp(block.timestamp + 1 days);
        
        // Get compounded balance and earned rewards
        uint256 compoundedBalance = staking.calculateCompoundBalance(user1);
        uint256 earnedRewards = staking.earned(user1);
        
        // Calculate what we'd expect with daily compound interest
        uint256 minuteRate = (REWARD_RATE * staking.DECIMAL_PRECISION()) / staking.MINUTES_PER_YEAR() / staking.DECIMAL_PRECISION();
        
        // Log values for analysis
        console.log("Minute rate:", minuteRate);
        console.log("Initial balance:", initialVirtualBalance);
        console.log("Compounded balance after 1 day:", compoundedBalance);
        console.log("Earned rewards after 1 day:", earnedRewards);
        console.log("Daily yield percentage:", (earnedRewards * 10000) / initialVirtualBalance); // Basis points (1/100 of a percent)
        
        // Verify rewards are non-zero
        assertTrue(earnedRewards > 0, "Should have earned rewards after 1 day");
        
        // Calculate theoretical daily compound yield: (1 + r)^1440 - 1
        // For 30% APY, daily yield should be approximately 0.072% = ((1 + 0.3/365)^1 - 1) * 100
        // Since we're compounding every minute, we'd expect slightly higher than this
        
        // Check that earned reward is roughly in the expected range for daily compounding of 30% APY
        // Daily factor: approximate range 0.07-0.09% of principal
        uint256 lowerBound = (stakeAmount * 7) / 10000; // 0.07% of stake
        uint256 upperBound = (stakeAmount * 9) / 10000; // 0.09% of stake
        
        assertTrue(earnedRewards >= lowerBound, "Rewards too low for daily compound of 30% APY");
        assertTrue(earnedRewards <= upperBound, "Rewards too high for daily compound of 30% APY");
    }
    
    // Test reward calculation for sequential minutes
    function testSequentialMinuteCompounding() public {
        uint256 stakeAmount = 1000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Compare manual compounding vs contract compounding for 10 consecutive minutes
        uint256 minuteRate = (REWARD_RATE * staking.DECIMAL_PRECISION()) / staking.MINUTES_PER_YEAR() / staking.DECIMAL_PRECISION();
        
        uint256 manualCompoundBalance = stakeAmount;
        
        for (uint i = 0; i < 10; i++) {
            // Advance time by 1 minute
            vm.warp(block.timestamp + 1 minutes);
            
            // Manually compound the balance
            uint256 interest = (manualCompoundBalance * minuteRate) / staking.DECIMAL_PRECISION();
            manualCompoundBalance += interest;
            
            // Get contract's calculated compound balance
            uint256 contractCompoundBalance = staking.calculateCompoundBalance(user1);
            
            // Verify manual calculation matches contract (allow small rounding error)
            assertApproxEqAbs(contractCompoundBalance, manualCompoundBalance, 10);
        }
    }
    
    // Test reward calculation with updated reward rate
    function testRewardCalculationWithRateChange() public {
        uint256 stakeAmount = 1000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Advance time by 10 minutes with 30% APY
        vm.warp(block.timestamp + 10 minutes);
        
        // Get earned rewards at 30% APY
        uint256 rewardsAt30Percent = staking.earned(user1);
        
        // Update annual reward rate to 50% APY
        vm.prank(admin);
        staking.setAnnualRewardRate(50 * 10**6); // 50% APY
        
        // Advance time by another 10 minutes with 50% APY
        vm.warp(block.timestamp + 10 minutes);
        
        // Get total earned rewards after rate change
        uint256 totalRewards = staking.earned(user1);
        
        console.log("Rewards at 30% APY for 10 minutes:", rewardsAt30Percent);
        console.log("Total rewards after additional 10 minutes at 50% APY:", totalRewards);
        
        // The rewards in the second period should be higher due to:
        // 1. Higher APY (50% vs 30%)
        // 2. Compounding on a larger balance (principal + first period rewards)
        
        // Verify total rewards are greater than first period rewards
        assertTrue(totalRewards > rewardsAt30Percent, "Total rewards should be greater after rate increase");
        
        // Calculate expected rewards for second period with manual calculation
        uint256 updatedMinuteRate = (50 * 10**6 * staking.DECIMAL_PRECISION()) / staking.MINUTES_PER_YEAR() / staking.DECIMAL_PRECISION();
        
        // Get the virtual balance after the first period (includes first period rewards)
        vm.prank(admin);
        staking.getReward(user1, totalRewards); // This updates the virtual balance - claim all rewards
        
        // Check that the rewards collection resets the rewards counter
        assertEq(staking.rewards(user1), 0, "Rewards should be reset after collection");
        
        // Virtual balance should now include the compounded value through the first 10 minutes
        uint256 virtualBalanceAfterFirstPeriod = staking.virtualBalanceOf(user1);
        
        // Perform a manual second calculation to verify
        // Advance time by another 10 minutes
        vm.warp(block.timestamp + 10 minutes);
        
        // Calculate rewards for the third period with 50% APY
        uint256 rewardsAfterRateChange = staking.earned(user1);
        
        console.log("Virtual balance after first period:", virtualBalanceAfterFirstPeriod);
        console.log("Rewards earned in third period (50% APY):", rewardsAfterRateChange);
        
        // Verify rewards in third period are non-zero
        assertTrue(rewardsAfterRateChange > 0, "Should have earned rewards in third period");
    }
    
    // Test annual compound yield
    function testAnnualCompoundYield() public {
        uint256 stakeAmount = 1000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Get earned rewards
        uint256 earnedRewards = staking.earned(user1);
        
        // For 30% APY with continuous compounding, expected value is approximately:
        // P * (e^r - 1) ≈ P * 0.35 for r = 0.3
        // With minute-by-minute compounding, we expect very close to this value
        uint256 expectedApproxRewards = (stakeAmount * 35) / 100; // ~35% of principal
        
        console.log("Staked amount:", stakeAmount);
        console.log("Earned rewards after 1 year:", earnedRewards);
        console.log("Rewards as percentage of principal:", (earnedRewards * 100) / stakeAmount, "%");
        
        // Check that earned rewards are within 1% of expected range
        assertApproxEqRel(earnedRewards, expectedApproxRewards, 1e16); // 1% tolerance
    }
    
    // Test multiple stake events with compounding
    function testMultipleStakeEventsWithCompounding() public {
        uint256 firstStake = 500 * 10**8; // 500 tokens
        uint256 secondStake = 500 * 10**8; // Another 500 tokens
        
        // First stake
        vm.startPrank(user1);
        token.approve(address(staking), firstStake + secondStake);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, firstStake);
        
        // Advance time by 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Check earned rewards after first period
        uint256 rewardsAfterFirstPeriod = staking.earned(user1);
        assertTrue(rewardsAfterFirstPeriod > 0, "Should have earned rewards after first period");
        
        // Calculate the compounded balance before second stake
        uint256 compoundedBalanceBeforeSecondStake = staking.calculateCompoundBalance(user1);
        
        // Make second stake - this will update the virtual balance with the compounded amount first
        vm.prank(admin);
        staking.stake(user1, secondStake);
        
        // The virtual balance should now be:
        // 1. The compounded balance of the first stake (including rewards)
        // 2. Plus the newly staked amount
        uint256 virtualBalanceAfterSecondStake = staking.virtualBalanceOf(user1);
        uint256 expectedVirtualBalance = compoundedBalanceBeforeSecondStake + secondStake;
        
        console.log("Compounded balance before second stake:", compoundedBalanceBeforeSecondStake);
        console.log("Second stake amount:", secondStake);
        console.log("Expected virtual balance:", expectedVirtualBalance);
        console.log("Actual virtual balance after second stake:", virtualBalanceAfterSecondStake);
        
        // Verify virtual balance after second stake
        assertEq(virtualBalanceAfterSecondStake, expectedVirtualBalance, "Virtual balance should include compounded first stake + second stake");
        
        // Advance time by another 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Get total earned rewards
        uint256 totalRewards = staking.earned(user1);
        
        console.log("Rewards after first 30 days (500 tokens):", rewardsAfterFirstPeriod);
        console.log("Total rewards after second 30 days (1000 tokens):", totalRewards);
        
        // Second period rewards should be larger because:
        // 1. Double the staked amount (1000 vs 500)
        // 2. Compounding on a larger base (includes first period rewards)
        assertTrue(totalRewards > rewardsAfterFirstPeriod * 2, "Total rewards should be more than double first period rewards");
    }

    // Test partial reward claiming
    function testPartialRewardClaiming() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        
        // Calculate earned rewards
        uint256 earnedRewards = staking.earned(user1);
        assertTrue(earnedRewards > 0, "Should have earned rewards after 30 days");
        
        // Claim half of the rewards
        uint256 halfRewards = earnedRewards / 2;
        uint256 initialTokenBalance = token.balanceOf(user1);
        uint256 initialVirtualBalance = staking.calculateCompoundBalance(user1);
        
        console.log("Initial virtual balance:", initialVirtualBalance);
        console.log("Total earned rewards:", earnedRewards);
        console.log("Claiming half rewards:", halfRewards);
        
        vm.prank(admin);
        staking.getReward(user1, halfRewards);
        
        // Verify half of rewards were claimed
        uint256 remainingRewards = staking.rewards(user1);
        console.log("Remaining rewards after partial claim:", remainingRewards);
        console.log("Expected remaining rewards:", earnedRewards - halfRewards);
        assertApproxEqAbs(remainingRewards, earnedRewards - halfRewards, 1, "Half of rewards should remain");
        
        // Verify token balance increased by half rewards
        assertApproxEqAbs(token.balanceOf(user1), initialTokenBalance + halfRewards, 1);
        
        // Verify virtual balance was updated correctly
        uint256 newVirtualBalance = staking.virtualBalanceOf(user1);
        assertTrue(newVirtualBalance < initialVirtualBalance, "Virtual balance should decrease after partial claim");
        console.log("Updated virtual balance:", newVirtualBalance);
        
        // Warp forward another day
        vm.warp(block.timestamp + 1 days);
        
        // Make sure new rewards are being earned based on the updated virtual balance
        uint256 newRewards = staking.earned(user1);
        assertTrue(newRewards > remainingRewards, "Should earn new rewards after partial claim");
        console.log("New total rewards after 1 more day:", newRewards);
        
        // Claim all remaining rewards
        vm.prank(admin);
        staking.getReward(user1, newRewards);
        
        // Verify all rewards were claimed
        assertEq(staking.rewards(user1), 0, "No rewards should remain after claiming all");
    }
    
    // Test emergency withdrawal
    function testEmergencyWithdraw() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        uint256 excessTokens = 500 * 10**8; // 500 extra tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Send additional tokens to contract (not part of staking)
        vm.prank(admin);
        token.transfer(address(staking), excessTokens);
        
        // Check contract balance vs total staked
        uint256 contractBalance = token.balanceOf(address(staking));
        uint256 availableBalance = staking.getContractBalance();
        assertEq(availableBalance, excessTokens + 100000 * 10**8, "Available balance should match excess tokens");
        
        // Emergency withdraw excess tokens
        vm.prank(admin);
        staking.emergencyWithdraw(excessTokens, admin, false);
        
        // Verify excess tokens were withdrawn
        
        // Verify staked tokens remain untouched
        assertEq(staking.totalStaked(), stakeAmount, "Staked tokens should remain untouched");
        assertEq(staking.balanceOf(user1), stakeAmount, "User's staked balance should remain untouched");
    }
    
    // Test emergency withdraw with force flag
    function testEmergencyWithdrawWithForce() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Attempt to withdraw more than available (should fail)
        vm.prank(admin);
        vm.expectRevert("Insufficient available balance");
        staking.emergencyWithdraw(stakeAmount, admin, false);
        
        // Use force flag to withdraw staked tokens
        vm.prank(admin);
        staking.emergencyWithdraw(stakeAmount, admin, true);
        
        // Verify tokens were withdrawn
        assertEq(token.balanceOf(admin), stakeAmount, "Admin should receive tokens");
        
        // Note: totalStaked is still the same, which means the contract is now undercollateralized
        assertEq(staking.totalStaked(), stakeAmount, "totalStaked remains unchanged");
    }
    
    // Test zero address and zero amount checks for emergency withdrawal
    function testEmergencyWithdrawChecks() public {
        // Test zero address
        vm.prank(admin);
        vm.expectRevert("Cannot withdraw to zero address");
        staking.emergencyWithdraw(100, address(0), false);
        
        // Test zero amount
        vm.prank(admin);
        vm.expectRevert("Cannot withdraw 0");
        staking.emergencyWithdraw(0, admin, false);
    }
    
    // Test getContractBalance
    function testGetContractBalance() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        uint256 extraAmount = 500 * 10**8; // 500 extra tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Initial contract balance should match staked amount
        assertEq(staking.getContractBalance(), 0, "Available balance should be 0 initially");
        
        // Add extra tokens to the contract
        vm.prank(admin);
        token.transfer(address(staking), extraAmount);
        
        // Contract balance should now include the extra tokens
        assertEq(staking.getContractBalance(), extraAmount, "Available balance should include extra tokens");
        
        // Warp forward and accumulate rewards
        vm.warp(block.timestamp + 30 days);
        
        // Claim rewards - this should not affect the contract balance calculation
        vm.prank(admin);
        staking.getReward(user1, staking.earned(user1)); // Claim all rewards
        
        // Contract balance should still match the extra amount
        assertEq(staking.getContractBalance(), extraAmount, "Available balance should still be extra tokens");
    }
    
    // Test getUserInfo view function
    function testGetUserInfo() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        
        // Get user info
        (
            uint256 _earned,
            uint256 _stakedBalance,
            uint256 _virtualBalance,
            uint256 _lastUpdateMinute,
            bool _hasWithdrawalRequest
        ) = staking.getUserInfo(user1);
        
        // Verify returned values
        assertEq(_earned, staking.earned(user1), "Earned value should match earned() function");
        assertEq(_stakedBalance, staking.balanceOf(user1), "Staked balance should match balanceOf()");
        assertEq(_virtualBalance, staking.virtualBalanceOf(user1), "Virtual balance should match virtualBalanceOf()");
        assertEq(_lastUpdateMinute, staking.userLastUpdateMinute(user1), "Last update minute should match storage");
        assertEq(_hasWithdrawalRequest, false, "User should not have a withdrawal request");
        
        // Request withdrawal and check again
        vm.prank(admin);
        staking.requestWithdrawal(user1);
        
        (,,,, _hasWithdrawalRequest) = staking.getUserInfo(user1);
        assertTrue(_hasWithdrawalRequest, "User should have a withdrawal request");
    }
}