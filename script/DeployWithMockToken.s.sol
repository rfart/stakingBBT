// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/CompoundStakingBBT.sol";
import "../test/CompoundStakingBBT.t.sol"; // Import to access MockBBT

contract DeployWithMockTokenScript is Script {
    function run() public {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the mock BBT token first
        MockBBT mockToken = new MockBBT();
        
        // Deploy the CompoundStakingBBT contract
        CompoundStakingBBT stakingContract = new CompoundStakingBBT(address(mockToken));
        
        // Transfer some tokens to the staking contract (for rewards)
        mockToken.transfer(address(stakingContract), 100_000 * 10**8);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        // Log deployment information
        console.log("MockBBT deployed at:", address(mockToken));
        console.log("CompoundStakingBBT deployed at:", address(stakingContract));
        console.log("Annual reward rate:", stakingContract.annualRewardRate());
        console.log("Wait time (seconds):", stakingContract.waitTime());
    }
}
