// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract StakingBBT is ReentrancyGuard, AccessControl {
    IERC20 public stakingToken;
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SELLON_ADMIN_ROLE = keccak256("SELLON_ADMIN_ROLE");
    
    // Reward rate in tokens per second
    uint256 public rewardRate;
    
    // Last time the reward was calculated
    uint256 public lastUpdateTime;
    
    // Reward per token stored
    uint256 public rewardPerTokenStored;
    
    // User address => rewardPerTokenStored
    mapping(address => uint256) public userRewardPerTokenPaid;
    
    // User address => rewards to be claimed
    mapping(address => uint256) public rewards;
    
    // Total staked
    uint256 public totalStaked;
    
    // User address => staked amount
    mapping(address => uint256) public balanceOf;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    // Update reward variables
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        rewardRate = 1e8; // Default reward rate: 1 token per second (adjusted for 8 decimals)
        lastUpdateTime = block.timestamp;
        
        // Set up the admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SELLON_ADMIN_ROLE, msg.sender);
    }

    // Calculate the reward per token
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        
        return rewardPerTokenStored + 
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e8) / totalStaked);
    }

    // Calculate earnings for an account
    function earned(address account) public view returns (uint256) {
        return (balanceOf[account] * 
            (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e8 + 
            rewards[account];
    }

    // Stake tokens
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        
        unchecked {
            totalStaked += amount;
            balanceOf[msg.sender] += amount;
        }
        
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount);
    }

    function stakeByAdmin(address user, uint256 amount) external onlyRole(SELLON_ADMIN_ROLE) nonReentrant updateReward(user) {
        require(amount > 0, "Cannot stake 0");

        unchecked {
            totalStaked += amount;
            balanceOf[user] += amount;
        }
        
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        emit Staked(user, amount);
    }

    

    // Withdraw staked tokens
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf[msg.sender] >= amount, "Not enough staked");
        
        totalStaked -= amount;

        unchecked{
            balanceOf[msg.sender] -= amount;
        }
        
        stakingToken.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }

    function withdrawByAdmin(address user, uint256 amount) public onlyRole(SELLON_ADMIN_ROLE) nonReentrant updateReward(user) {
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf[user] >= amount, "Not enough staked");
        
        totalStaked -= amount;

        unchecked{
            balanceOf[user] -= amount;
        }
        
        stakingToken.transfer(user, amount);
        
        emit Withdrawn(user, amount);
    }

    // Claim rewards
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            delete rewards[msg.sender];

            stakingToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getRewardByAdmin(address user) public onlyRole(SELLON_ADMIN_ROLE) nonReentrant updateReward(user) {
        uint256 reward = rewards[user];
        if (reward > 0) {
            delete rewards[user];
            
            stakingToken.transfer(user, reward);
            emit RewardPaid(user, reward);
        }
    }

    // Withdraw stake and claim rewards in one transaction
    function exit() external {
        withdraw(balanceOf[msg.sender]);
        getReward();
    }

    function exitByAdmin(address user) external onlyRole(SELLON_ADMIN_ROLE) {
        withdrawByAdmin(user, balanceOf[user]);
        getRewardByAdmin(user);
    }

    // Only admin can set reward rate
    function setRewardRate(uint256 _rewardRate) external onlyRole(ADMIN_ROLE) updateReward(address(0)) {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    // Admin can add reward tokens to the contract
    function addRewardTokens(uint256 amount) external onlyRole(ADMIN_ROLE) {
        stakingToken.transferFrom(msg.sender, address(this), amount);
    }
}