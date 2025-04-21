# StakingBBT: User Flow & Reward Calculation

## User Flow

### Regular Users

1. **Staking Tokens**
   - Users call the `stake(uint256 amount)` function
   - The system updates their rewards before staking
   - Users transfer tokens to the contract
   - The contract tracks the staked amount under the user's address

2. **Withdrawing Tokens**
   - Users call the `withdraw(uint256 amount)` function
   - The system updates their rewards before withdrawal
   - Users receive their staked tokens back
   - The contract reduces the staked amount for the user

3. **Claiming Rewards**
   - Users call the `getReward()` function
   - The system calculates and transfers earned rewards
   - Reward balance is reset to zero

4. **Combined Withdrawal and Claim**
   - Users call the `exit()` function
   - The system withdraws all staked tokens and claims all rewards in one transaction

### Admin Functions

1. **Staking on Behalf of Users**
   - SELLON_ADMIN calls `stakeByAdmin(address user, uint256 amount)`
   - The admin pays for the tokens, but they're credited to the user

2. **Withdrawing on Behalf of Users**
   - SELLON_ADMIN calls `withdrawByAdmin(address user, uint256 amount)`
   - The tokens are sent directly to the user

3. **Claiming Rewards on Behalf of Users**
   - SELLON_ADMIN calls `getRewardByAdmin(address user)`
   - The system calculates and transfers earned rewards to the user
   - User's reward balance is reset to zero

4. **Combined Exit on Behalf of Users**
   - SELLON_ADMIN calls `exitByAdmin(address user)`
   - All staked tokens are withdrawn and rewards claimed for the user

5. **Setting Reward Rate**
   - ADMIN calls `setRewardRate(uint256 _rewardRate)`
   - Updates the rate at which rewards accrue per second

6. **Adding Reward Tokens**
   - ADMIN calls `addRewardTokens(uint256 amount)`
   - Adds more tokens to the reward pool

## View Functions

The contract provides several view functions that allow users and applications to query the current state without making transactions:

### Token Information
- `stakingToken()`: Returns the address of the ERC20 token being staked/rewarded (In our case, it's BBT smart contract address)

### Reward Calculation Functions
- `rewardPerToken()`: Returns the current accumulated reward per staked token
- `earned(address account)`: Returns the amount of rewards an account has earned but not yet claimed

### User Balance Information
- `balanceOf(address account)`: Returns the amount of tokens staked by a specific user
- `rewards(address account)`: Returns the amount of rewards currently accumulated for a user
- `userRewardPerTokenPaid(address account)`: Returns the reward per token value when the user last interacted with the contract

### Global State Variables
- `rewardRate()`: Returns the current reward rate per second
- `lastUpdateTime()`: Returns the timestamp when rewards were last updated
- `rewardPerTokenStored()`: Returns the last stored reward per token value
- `totalStaked()`: Returns the total amount of tokens staked in the contract

### Access Control
- `hasRole(bytes32 role, address account)`: Returns whether an account has a specific role
- Standard AccessControl view functions for querying role information

These view functions are gas-free (when called off-chain) and provide all the necessary information for users to monitor their staking positions and rewards.


## Reward Calculation -TBD-

### Core Concepts

1. **Reward Rate**: The number of tokens distributed per second to the entire staking pool
2. **Last Update Time**: The timestamp when rewards were last calculated
3. **Reward Per Token Stored**: The accumulated reward per token up to the last update
4. **User Reward Per Token Paid**: The accumulated reward per token up to the user's last action
5. **Rewards**: The user's accumulated rewards that haven't been claimed yet

### Calculation Process

1. **Reward Per Token Calculation**:
   ```
   rewardPerToken = rewardPerTokenStored + 
                   ((currentTime - lastUpdateTime) * rewardRate * 1e8) / totalStaked
   ```
   This calculates how many rewards each staked token has earned since the last update.

2. **User Earnings Calculation**:
   ```
   earned = (userStakedBalance * (rewardPerToken - userRewardPerTokenPaid)) / 1e8 + 
            alreadyAccumulatedRewards
   ```
   This calculates how many rewards a specific user has earned based on their stake.

3. **Update Process**:
   - Every time a user interacts with the contract (stake, withdraw, claim), their rewards are updated
   - The reward calculation uses the time difference since the last update to determine new rewards
   - After calculation, the lastUpdateTime is set to the current time

### Example

1. User A stakes 1000 tokens (with 8 decimals, this is 1000 * 10^8)
2. Reward rate is set to 1 token per second (1 * 10^8)
3. After 1 day (86,400 seconds), User A would earn:
   ```
   Reward = 86,400 seconds * 1 token per second = 86,400 tokens
   ```

If multiple users are staking, rewards are distributed proportionally to their stake in the total pool.

## Important Notes

1. The calculations use 8 decimal places to match the token's decimal configuration
2. Rewards are continuously accruing as time passes
3. All reward calculations are done on-chain at the time of interaction
4. No rewards are distributed when totalStaked is zero
