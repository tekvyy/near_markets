# Prediction Markets with Near Protocol

This is a README file for the Prediction Markets project, 
a decentralized application (DApp) that utilizes Near Protocol, 
Near Rust smart contracts, Aurora EVM, and Mintbase SDK to create prediction markets, 
settle them, and mint NFTs for users who win the prediction market pools.

## Project Overview

### 1. Near Protocol
[Near Protocol](https://near.org/) is a blockchain platform that offers a secure, scalable, and developer-friendly environment for building decentralized applications. It provides smart contract functionality, which we use to create prediction markets.

### 2. Near Rust Smart Contracts
We have implemented smart contracts in Rust that enable the creation and management of prediction markets on the Near Protocol blockchain. These smart contracts facilitate the betting process, pool management, and settlement of prediction markets.

### 3. Aurora EVM
[Aurora](https://aurora.dev/) is a bridge between the Ethereum Virtual Machine (EVM) and the Near Protocol blockchain. It allows us to run Solidity smart contracts originally designed for Ethereum on the Near Protocol blockchain. We use Aurora to execute smart contracts related to prediction market settlements and payouts.

### 4. Mintbase SDK
[Mintbase](https://mintbase.io/) is a platform for creating and managing NFTs (Non-Fungible Tokens). We utilize the Mintbase SDK to mint NFTs when prediction markets are settled, and users win the pool. These NFTs can represent unique assets or rewards associated with the prediction markets.

## Dependencies

Before you can run the Prediction Markets DApp, you need to ensure you have the following dependencies installed:

- [Near CLI](https://docs.near.org/docs/tools/near-cli) - Near Protocol's command-line interface for interacting with the blockchain.
- [Rust](https://www.rust-lang.org/) - Required for building and deploying Near smart contracts.
- [Aurora EVM](https://aurora.dev/docs/getting-started/installation) - To run Solidity smart contracts on Near.
- [Mintbase SDK](https://github.com/Mintbase/mintbase-sdk) - Required for minting NFTs.

## Installation

1. Build Near Contracts Project:

   ```bash
   cd near_markets/near_rust_contracts
   ./build.sh

2. Build Solidity Contracts using Aurora SDK 

   ```bash
   cd near_markets/aurora_solidity_contracts
   


# NEAR Smart Contract for Prediction Markets

Below are the Near CLI Commands used to Run the various methods of the Smart contract

Deploy Smart Contract
```bash
near dev-deploy  --wasmFile ./target/wasm32-unknown-unknown/release/near_rust_contracts.wasm --accountId userid.testnet
```

Create Prediction markets
```bash
near call userid.testnet create_market '{"description": "will india win world cup 2023?", "outcomes": ["YES", "NO"]}' --accountId userid.testnet
```

Get Current Live markets on the Contract
```bash

near view userid.testnet get_markets '{"from_index":0, "limit": 1}'
```

Vote for One of the Option of Prediction Market
```bash

near call userid.testnet place_bet '{"market_id": 0, "prediction": "YES"}' --accountId userid.testnet --amount 0.1

```
Settle the Market and share rewards to winners (To be moved to an oracle)
```bash
near call userid.testnet settle_market '{"market_id": 0, "winning_outcome": "YES"}' --accountId userid.testnet
```

