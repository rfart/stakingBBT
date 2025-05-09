// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StakingBBT
 * @dev Contract for staking BBT tokens with fixed annual rewards
 * @custom:security-contact security@example.com
 */
contract StakingBBT is ReentrancyGuard, AccessControl {
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
     * @notice Calculate rewards earned for an account
     * @dev Calculates time-based rewards using minute precision
     * @param account Address for which to calculate rewards
     * @return Amount of rewards earned
     */
    function earned(address account) public view returns (uint256) {
        if (balanceOf[account] == 0) {
            return rewards[account];
        }
        
        uint256 currentMinute = getCurrentMinute();
        uint256 lastUpdateMinuteForUser = userLastUpdateMinute[account];
        
        // If already updated this minute, return current rewards
        if (currentMinute <= lastUpdateMinuteForUser) {
            return rewards[account];
        }
        
        // Calculate minutes elapsed since last update
        uint256 minutesElapsed = currentMinute - lastUpdateMinuteForUser;
        
        // Calculate per-minute reward rate (annual rate divided by minutes in a year)
        // Adjusted for 8 decimal precision
        uint256 minuteRate = (annualRewardRate * DECIMAL_PRECISION) / MINUTES_PER_YEAR / DECIMAL_PRECISION;
        
        // Calculate new rewards (using 8 decimal precision)
        uint256 newRewards = (balanceOf[account] * minuteRate * minutesElapsed) / DECIMAL_PRECISION;
        
        return rewards[account] + newRewards;
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
        
        totalStaked -= amount;

        unchecked{
            balanceOf[user] -= amount;
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