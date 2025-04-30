// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/CompoundStakingBBT.sol";

contract DeployCompoundStakingBBT is Script {
    function run() public {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("BBT_ADDRESS_TEST");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the CompoundStakingBBT contract
        CompoundStakingBBT stakingContract = new CompoundStakingBBT(tokenAddress);
        
        // Optional: Set custom parameters if needed
        // For example, set a different reward rate (40% annually)
        // stakingContract.setAnnualRewardRate(40_000_000); // 40%
        
        // Optional: Set a different wait time (2 days)
        // stakingContract.setWaitTime(2 days);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        // Log deployment information
        console.log("CompoundStakingBBT deployed at:", address(stakingContract));
        console.log("Token address:", tokenAddress);
        console.log("Annual reward rate:", stakingContract.annualRewardRate());
        console.log("Wait time (seconds):", stakingContract.waitTime());
    }
}
