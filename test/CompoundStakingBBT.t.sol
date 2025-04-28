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
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Record initial state
        uint256 initialVirtualBalance = staking.virtualBalanceOf(user1);
        assertEq(initialVirtualBalance, stakeAmount, "Initial virtual balance should equal staked amount");
        
        // Warp forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Check compound balance calculation
        uint256 compoundedBalance = staking.calculateCompoundBalance(user1);
        assertTrue(compoundedBalance > initialVirtualBalance, "Balance should increase due to compound interest");
        
        // Perform an action to trigger the reward update
        vm.prank(admin);
        staking.getReward(user1);
        
        // Check that virtual balance has been updated with compound interest
        uint256 updatedVirtualBalance = staking.virtualBalanceOf(user1);
        assertTrue(updatedVirtualBalance > initialVirtualBalance, "Virtual balance should be updated with compound interest");
        assertEq(updatedVirtualBalance, compoundedBalance, "Virtual balance should match the calculated compound balance");
    }
    
    function testWithdraw() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        uint256 withdrawAmount = 400 * 10**8; // 400 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward to accumulate some rewards
        vm.warp(block.timestamp + 30 days);
        
        // Record virtual balance before withdrawal
        uint256 virtualBalanceBefore = staking.virtualBalanceOf(user1);
        
        // Withdraw partial amount
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, withdrawAmount);
        staking.withdraw(user1, withdrawAmount);
        
        // Calculate expected remaining percentage (60% of original stake)
        uint256 expectedRemainingPercentage = 60 * 1e8; // 60% scaled by 1e8
        
        // Check actual balances
        assertEq(staking.balanceOf(user1), stakeAmount - withdrawAmount, "Staked balance should be reduced by withdraw amount");
        assertEq(staking.totalStaked(), stakeAmount - withdrawAmount, "Total staked should be reduced by withdraw amount");
        
        // Check virtual balance has been reduced proportionally
        uint256 virtualBalanceAfter = staking.virtualBalanceOf(user1);
        uint256 expectedVirtualBalance = (virtualBalanceBefore * expectedRemainingPercentage) / 100e8;
        
        // Allow for minimal rounding errors
        assertApproxEqRel(virtualBalanceAfter, expectedVirtualBalance, 1e15); // 0.1% tolerance
        
        // Check token balances
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - stakeAmount + withdrawAmount);
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
        assertEq(initialRewards, 0, "Initial rewards should be zero");
        
        // Warp forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        
        // Check earned rewards
        uint256 earnedRewards = staking.earned(user1);
        assertTrue(earnedRewards > 0, "Should have earned rewards after 30 days");
        
        // Check virtual balance is greater than initial stake (compound interest)
        uint256 virtualBalance = staking.calculateCompoundBalance(user1);
        assertTrue(virtualBalance > stakeAmount, "Virtual balance should increase with compound interest");
        
        // Claim rewards
        uint256 initialTokenBalance = token.balanceOf(user1);
        
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit RewardPaid(user1, earnedRewards);
        staking.getReward(user1);
        
        // Verify rewards are claimed
        assertEq(staking.rewards(user1), 0, "Rewards should be zero after claim");
        
        // Verify tokens were transferred
        assertEq(token.balanceOf(user1), initialTokenBalance + earnedRewards);
    }
    
    function testExit() public {
        uint256 stakeAmount = 1_000 * 10**8; // 1,000 tokens
        
        // Setup: user1 stakes tokens
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        vm.stopPrank();
        
        vm.prank(admin);
        staking.stake(user1, stakeAmount);
        
        // Warp forward to accumulate rewards
        vm.warp(block.timestamp + 60 days);
        
        uint256 earnedRewards = staking.earned(user1);
        assertTrue(earnedRewards > 0, "Should have earned rewards after 60 days");
        
        // Record initial token balance
        uint256 initialTokenBalance = token.balanceOf(user1);
        
        // Exit staking (withdraw all + claim rewards)
        vm.prank(admin);
        staking.exit(user1);
        
        // Verify all staked tokens and rewards are withdrawn
        assertEq(staking.balanceOf(user1), 0, "Staked balance should be zero after exit");
        assertEq(staking.rewards(user1), 0, "Rewards should be zero after exit");
        assertEq(staking.virtualBalanceOf(user1), 0, "Virtual balance should be zero after exit");
        
        // Verify token balance increased by staked amount + rewards
        assertEq(token.balanceOf(user1), initialTokenBalance + stakeAmount + earnedRewards);
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
        staking.getReward(user1); // This updates the virtual balance
        
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
}