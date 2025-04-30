// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CompoundStakingBBT
 * @dev Contract for staking BBT tokens with compound interest rewards
 * @custom:security-contact security@example.com
 */
contract CompoundStakingBBT is ReentrancyGuard, AccessControl {
    IERC20 immutable public stakingToken;
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SELLON_ADMIN_ROLE = keccak256("SELLON_ADMIN_ROLE");
    
    // Annual reward rate in percentage (scaled by 1e8)
    uint256 public annualRewardRate;
    
    // Last time the reward was calculated (timestamp in minutes)
    uint256 public lastUpdateMinute;
    
    // User address => last update minute
    mapping(address => uint256) public userLastUpdateMinute;
    
    // User address => rewards to be claimed
    mapping(address => uint256) public rewards;
    
    // Total staked
    uint256 public totalStaked;
    
    // User address => staked amount
    mapping(address => uint256) public balanceOf;
    
    // User address => virtual balance (including compounded rewards)
    mapping(address => uint256) public virtualBalanceOf;
    
    // Constants for time calculations
    uint256 public constant MINUTES_PER_YEAR = 525600; // 60 * 24 * 365
    uint256 public constant DECIMAL_PRECISION = 1e8; // For 8 decimal token
    uint256 private constant SCALE = 1e8; // 10^8 scaling for fixed-point math
    
    // Waiting period for withdrawals in seconds
    uint256 public waitTime;
    
    // User address => requested withdrawal timestamp
    mapping(address => uint256) public withdrawalRequests;
    
    // User address => amount requested for withdrawal
    mapping(address => uint256) public withdrawalAmounts;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event AnnualRewardRateUpdated(uint256 newRate);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event WaitTimeUpdated(uint256 newWaitTime);

    /**
     * @notice Get current minute timestamp
     * @dev Used for reward calculations to reduce gas costs
     * @return Current block timestamp in minutes
     */
    function getCurrentMinute() public view returns (uint256) {
        return block.timestamp / 1 minutes;
    }

    /**
     * @dev Modifier to calculate and update reward for a specific account
     * @param account The address for which to update rewards
     */
    modifier updateReward(address account) {
        uint256 currentMinute = getCurrentMinute();
        
        if (account != address(0)) {
            rewards[account] = earned(account);
            userLastUpdateMinute[account] = currentMinute;
            // Update virtual balance when updating rewards
            if (balanceOf[account] > 0) {
                virtualBalanceOf[account] = calculateCompoundBalance(account);
            }
        }
        
        lastUpdateMinute = currentMinute;
        _;
    }

    /**
     * @notice Initialize staking contract with token
     * @dev Sets up roles and default reward rate
     * @param _stakingToken Address of the ERC20 token to stake
     */
    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        annualRewardRate = 3 * 10**7; // 0.3 * 10^8 = 30% (scaled by 1e8 for 8 decimal token)
        lastUpdateMinute = getCurrentMinute();
        waitTime = 2 minutes;
        
        // Set up the admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SELLON_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Calculate the compound balance for an account
     * @dev Uses the compound interest formula: P * (1 + r)^t
     * @param account Address for which to calculate compound balance
     * @return Compounded balance
     */
    function calculateCompoundBalance(address account) public view returns (uint256) {
        uint256 currentMinute = getCurrentMinute();
        uint256 lastUpdateMinuteForUser = userLastUpdateMinute[account];
        uint256 accountBalance = balanceOf[account];
        uint256 accountVirtualBalance = virtualBalanceOf[account];

        uint256 baseBalance = accountVirtualBalance == 0 ? accountBalance : accountVirtualBalance;

        // If already updated this minute or no balance, return current virtual balance
        if (currentMinute <= lastUpdateMinuteForUser || accountBalance == 0) {
            return baseBalance;
        }
        
        // Calculate minutes elapsed since last update
        uint256 minutesElapsed = currentMinute - lastUpdateMinuteForUser;
        
        // Calculate per-minute rate (r) = (1 + annual_rate)^(1/MINUTES_PER_YEAR) - 1
        // For small rates, we can approximate this using: r ≈ annual_rate / MINUTES_PER_YEAR
        uint256 minuteRate = (annualRewardRate * DECIMAL_PRECISION) / MINUTES_PER_YEAR / DECIMAL_PRECISION;
        
        // Convert to scaled rate for fixed-point math (adding SCALE as 1.0)
        uint256 scaledMinuteRate = SCALE + ((minuteRate * SCALE) / DECIMAL_PRECISION);
        
        // Calculate (1 + r)^t using exponentiation by squaring
        uint256 compoundFactor = pow(scaledMinuteRate, minutesElapsed);
        
        // Apply compound factor to the principal
        uint256 compoundBalance = (baseBalance * compoundFactor) / SCALE;
        
        return compoundBalance;
    }

    /**
     * @dev Exponentiation by squaring for efficient calculation of (base^exponent)
     * @param base The base value (scaled by SCALE)
     * @param exponent The exponent
     * @return The result of base^exponent (scaled by SCALE)
     */
    function pow(uint256 base, uint256 exponent) private pure returns (uint256) {
        uint256 result = SCALE;
        while (exponent != 0) {
            if (exponent % 2 == 1) {
                result = (result * base) / SCALE;
            }
            base = (base * base) / SCALE;
            exponent /= 2;
        }
        return result;
    }

    /**
     * @notice Calculate rewards earned for an account
     * @dev Calculates compound interest rewards
     * @param account Address for which to calculate rewards
     * @return Amount of rewards earned
     */
    function earned(address account) public view returns (uint256) {
        uint256 _balanceOf = balanceOf[account];
        uint256 _virtualBalanceOf = virtualBalanceOf[account];

        // If user has a pending withdrawal request, don't calculate new rewards
        if (_balanceOf == 0 || withdrawalRequests[account] > 0) {
            return rewards[account];
        }
        
        uint256 compoundBalance = calculateCompoundBalance(account);
        uint256 initialBalance = _virtualBalanceOf == 0 ? _balanceOf : _virtualBalanceOf;
        
        // The earned rewards are the difference between compound balance and initial balance
        return rewards[account] + (compoundBalance - initialBalance);
    }

    /**
     * @notice Stake tokens for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address that is staking the tokens
     * @param amount Amount of tokens to stake
     */
    function stake(address user, uint256 amount) external nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        require(amount > 0, "Cannot stake 0");

        unchecked {
            totalStaked += amount;
            balanceOf[user] += amount;
            virtualBalanceOf[user] += amount;
        }
        
        stakingToken.transferFrom(user, address(this), amount);
        
        emit Staked(user, amount);
    }

    /**
     * @notice Request to withdraw all staked tokens
     * @dev Initiates the withdrawal process with waiting period
     * @param user Address requesting the withdrawal
     */
    function requestWithdrawal(address user) external nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        uint256 userBalance = balanceOf[user];
        require(userBalance > 0, "No tokens staked");
        require(withdrawalRequests[user] == 0, "Withdrawal already pending");
        
        withdrawalRequests[user] = block.timestamp;
        withdrawalAmounts[user] = userBalance;
        
        uint256 unlockTime = block.timestamp + waitTime;
        
        emit WithdrawalRequested(user, userBalance, unlockTime);
    }

    /**
     * @notice Complete withdrawal after waiting period
     * @dev Can only be called after the waiting period has elapsed
     * @param user Address to complete withdrawal for
     */
    function completeWithdrawal(address user) external nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        require(withdrawalRequests[user] > 0, "No withdrawal request");
        require(block.timestamp >= withdrawalRequests[user] + waitTime, "Waiting period not over");

        uint256 amount = withdrawalAmounts[user];
        // Clear withdrawal request
        withdrawalRequests[user] = 0;
        withdrawalAmounts[user] = 0;
        
        // Process withdrawal
        _withdraw(user, amount);
    }

    /**
     * @notice Cancel a pending withdrawal request
     * @dev Allows a user to cancel their withdrawal request
     * @param user Address to cancel withdrawal for
     */
    function cancelWithdrawal(address user) external nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        require(withdrawalRequests[user] > 0, "No withdrawal request");
        
        // Clear withdrawal request
        withdrawalRequests[user] = 0;
        withdrawalAmounts[user] = 0;
    }

    /**
     * @notice Withdraw all staked tokens for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address to withdraw tokens for
     */
    function withdraw(address user) public nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        require(withdrawalRequests[user] == 0, "Withdrawal request pending, use completeWithdrawal");
        uint256 userBalance = balanceOf[user];
        require(userBalance > 0, "No tokens staked");
        _withdraw(user, userBalance);
    }

    /**
     * @notice Internal function to withdraw staked tokens
     * @param user Address to withdraw tokens for
     * @param amount Amount of tokens to withdraw
     */
    function _withdraw(address user, uint256 amount) internal {
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf[user] >= amount, "Not enough staked");
        
        // Since we're withdrawing everything, we can directly set virtual balance to 0
        totalStaked -= amount;
        balanceOf[user] = 0;
        virtualBalanceOf[user] = 0;
        
        stakingToken.transfer(user, amount);
        
        emit Withdrawn(user, amount);
    }

    /**
     * @notice Claim accumulated rewards for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address to claim rewards for
     * @param amount Amount of rewards to claim, 0 for claiming all rewards
     */
    function getReward(address user, uint256 amount) public nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        _getReward(user, amount);
    }

    /**
     * @notice Internal function to claim accumulated rewards
     * @param user Address to claim rewards for
     * @param amount Amount of rewards to claim, 0 for claiming all rewards
     */
    function _getReward(address user, uint256 amount) internal {
        uint256 reward = rewards[user];
        if (reward > 0) {
            // If amount is 0 or greater than available rewards, claim all rewards
            uint256 claimAmount = (amount == 0 || amount > reward) ? reward : amount;
            
            // Update rewards balance
            rewards[user] = reward - claimAmount;
            
            // When updating rewards partially, we need to ensure virtual balance is updated
            // to reflect the current compounded value for future calculations
            if (balanceOf[user] > 0) {
                virtualBalanceOf[user] = calculateCompoundBalance(user);
            }
            
            stakingToken.transfer(user, claimAmount);
            emit RewardPaid(user, claimAmount);
        }
    }

    /**
     * @notice Withdraw all staked tokens and rewards for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address to exit staking for
     */
    function exit(address user) external nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        uint256 userBalance = balanceOf[user];
        if (userBalance > 0) {
            _withdraw(user, userBalance);
        }
        _getReward(user, 0); // Claim all rewards by passing 0
    }

    /**
     * @notice Update the annual reward rate
     * @dev Can only be called by address with ADMIN_ROLE
     * @param _annualRewardRate New annual reward rate (scaled by DECIMAL_PRECISION)
     */
    function setAnnualRewardRate(uint256 _annualRewardRate) external onlyRole(ADMIN_ROLE) updateReward(address(0)) {
        annualRewardRate = _annualRewardRate;
        emit AnnualRewardRateUpdated(_annualRewardRate);
    }

    /**
     * @notice Update the waiting period for withdrawals
     * @dev Can only be called by address with ADMIN_ROLE
     * @param _waitTime New waiting period in seconds
     */
    function setWaitTime(uint256 _waitTime) external onlyRole(ADMIN_ROLE) {
        waitTime = _waitTime;
        emit WaitTimeUpdated(_waitTime);
    }

    /**
     * @notice Emergency withdraw tokens that are not part of the staking pool
     * @dev Can only be called by address with ADMIN_ROLE
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to send tokens to
     */
    function emergencyWithdraw(uint256 amount, address recipient, bool forceWithdraw) external nonReentrant onlyRole(ADMIN_ROLE) {
        require(recipient != address(0), "Cannot withdraw to zero address");
        require(amount > 0, "Cannot withdraw 0");
        
        // Calculate available balance (total balance - staked tokens)
        uint256 availableBalance = stakingToken.balanceOf(address(this)) - totalStaked;
        if (!forceWithdraw) {
            require(amount <= availableBalance, "Insufficient available balance");
        }
        
        stakingToken.transfer(recipient, amount);
    }

    /**
     * @notice Get the contract balance excluding staked tokens
     * @dev Returns the amount of tokens that can be withdrawn by the admin
     * @return Available balance not allocated to staking
     */
    function getContractBalance() external view returns (uint256) {
        uint256 totalBalance = stakingToken.balanceOf(address(this));
        uint256 availableBalance = totalBalance > totalStaked ? totalBalance - totalStaked : 0;
        return availableBalance;
    }

    /**
     * @notice Get all essential user information in a single call
     * @dev Retrieves user's earned rewards, staked balance, and last update minute
     * @param user Address of the user to get information for
     * @return _earned The earned rewards for the user
     * @return _stakedBalance The user's staked balance
     * @return _virtualBalance The user's virtual balance with compounded interest
     * @return _lastUpdateMinute The last time the user's rewards were updated (in minutes)
     * @return _hasWithdrawalRequest Whether the user has a pending withdrawal request
     */
    function getUserInfo(address user) external view returns (
        uint256 _earned,
        uint256 _stakedBalance,
        uint256 _virtualBalance,
        uint256 _lastUpdateMinute,
        bool _hasWithdrawalRequest
    ) {
        return (
            earned(user),
            balanceOf[user],
            virtualBalanceOf[user],
            userLastUpdateMinute[user],
            withdrawalRequests[user] > 0
        );
    }
}
