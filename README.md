## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

# Compound Staking BBT

A staking contract for BBT tokens with compound interest rewards.

## Deployment Instructions

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- An Ethereum node URL (Infura, Alchemy, etc.)
- A wallet private key with sufficient ETH for deployment gas

### Environment Setup

Create a `.env` file with the following variables:

```
PRIVATE_KEY=your_private_key_here_without_0x_prefix
RPC_URL=your_ethereum_node_url
TOKEN_ADDRESS=address_of_bbt_token_contract
```

Load environment variables:

```bash
source .env
```

### Deploy on Mainnet or Testnet

Deploy using an existing token:

```bash
forge script script/DeployCompoundStakingBBT.s.sol --rpc-url $TESTNET --broadcast --verify
```

Or deploy with a mock token (for testing):

```bash
forge script script/DeployWithMockToken.s.sol --rpc-url $TESTNET --broadcast --verify
```

### Post-Deployment Steps

1. Verify the contract on Etherscan (if the `--verify` flag didn't work automatically):

```bash
forge verify-contract <DEPLOYED_CONTRACT_ADDRESS> src/CompoundStakingBBT.sol:CompoundStakingBBT --chain-id <CHAIN_ID> --watch
```

2. Grant the SELLON_ADMIN_ROLE to any additional addresses that need it:

```bash
cast send <STAKING_CONTRACT_ADDRESS> "grantRole(bytes32,address)" \
  $(cast keccak "SELLON_ADMIN_ROLE") <NEW_ADMIN_ADDRESS> \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Contract Settings

- **Annual Reward Rate**: Default is 30%, can be changed by admin
- **Wait Time**: Default is 1 day (86400 seconds), can be changed by admin
