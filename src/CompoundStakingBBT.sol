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
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event AnnualRewardRateUpdated(uint256 newRate);

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
        
        // If already updated this minute or no balance, return current virtual balance
        if (currentMinute <= lastUpdateMinuteForUser || balanceOf[account] == 0) {
            return virtualBalanceOf[account] == 0 ? balanceOf[account] : virtualBalanceOf[account];
        }
        
        // Calculate minutes elapsed since last update
        uint256 minutesElapsed = currentMinute - lastUpdateMinuteForUser;
        
        // Calculate per-minute rate (r) = (1 + annual_rate)^(1/MINUTES_PER_YEAR) - 1
        // For small rates, we can approximate this using: r ≈ annual_rate / MINUTES_PER_YEAR
        uint256 minuteRate = (annualRewardRate * DECIMAL_PRECISION) / MINUTES_PER_YEAR / DECIMAL_PRECISION;
        
        // Calculate compound multiplier: (1 + r)^t
        // Use iterative approach for compound calculation
        uint256 baseBalance = virtualBalanceOf[account] == 0 ? balanceOf[account] : virtualBalanceOf[account];
        uint256 compoundBalance = baseBalance;
        
        // Apply the compound interest for each minute
        for (uint256 i = 0; i < minutesElapsed; i++) {
            uint256 interest = (compoundBalance * minuteRate) / DECIMAL_PRECISION;
            compoundBalance += interest;
        }
        
        return compoundBalance;
    }

    /**
     * @notice Calculate rewards earned for an account
     * @dev Calculates compound interest rewards
     * @param account Address for which to calculate rewards
     * @return Amount of rewards earned
     */
    function earned(address account) public view returns (uint256) {
        if (balanceOf[account] == 0) {
            return rewards[account];
        }
        
        uint256 compoundBalance = calculateCompoundBalance(account);
        uint256 initialBalance = virtualBalanceOf[account] == 0 ? balanceOf[account] : virtualBalanceOf[account];
        
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
            
            // Update virtual balance with the newly staked amount
            if (virtualBalanceOf[user] == 0) {
                virtualBalanceOf[user] = balanceOf[user];
            } else {
                virtualBalanceOf[user] += amount;
            }
        }
        
        stakingToken.transferFrom(user, address(this), amount);
        
        emit Staked(user, amount);
    }

    /**
     * @notice Withdraw staked tokens for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address to withdraw tokens for
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(address user, uint256 amount) public nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        _withdraw(user, amount);
    }

    /**
     * @notice Internal function to withdraw staked tokens
     * @param user Address to withdraw tokens for
     * @param amount Amount of tokens to withdraw
     */
    function _withdraw(address user, uint256 amount) internal {
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf[user] >= amount, "Not enough staked");
        
        // Calculate what percentage of the balance is being withdrawn
        uint256 withdrawRatio = (amount * DECIMAL_PRECISION) / balanceOf[user];
        
        // Reduce virtual balance proportionally
        uint256 virtualAmountToReduce = (virtualBalanceOf[user] * withdrawRatio) / DECIMAL_PRECISION;
        
        totalStaked -= amount;

        unchecked {
            balanceOf[user] -= amount;
            virtualBalanceOf[user] -= virtualAmountToReduce;
        }
        
        stakingToken.transfer(user, amount);
        
        emit Withdrawn(user, amount);
    }

    /**
     * @notice Claim accumulated rewards for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address to claim rewards for
     */
    function getReward(address user) public nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        _getReward(user);
    }

    /**
     * @notice Internal function to claim accumulated rewards
     * @param user Address to claim rewards for
     */
    function _getReward(address user) internal {
        uint256 reward = rewards[user];
        if (reward > 0) {
            delete rewards[user];
            
            stakingToken.transfer(user, reward);
            emit RewardPaid(user, reward);
        }
    }

    /**
     * @notice Withdraw all staked tokens and rewards for a user
     * @dev Can only be called by address with SELLON_ADMIN_ROLE
     * @param user Address to exit staking for
     */
    function exit(address user) external nonReentrant onlyRole(SELLON_ADMIN_ROLE) updateReward(user) {
        _withdraw(user, balanceOf[user]);
        _getReward(user);
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
}
