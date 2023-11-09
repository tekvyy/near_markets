#!/bin/sh
#near dev-deploy --wasmFile ./target/wasm32-unknown-unknown/release/hello_near.wasm

#near deploy dev-1699540518245-37645438973376 --wasmFile ./target/wasm32-unknown-unknown/release/near_rust_contracts.wasm
#near dev-deploy  --wasmFile ./target/wasm32-unknown-unknown/release/near_rust_contracts.wasm --accountId userid.testnet

#near call userid.testnet new --accountId=userid.testnet
#near call userid.testnet create_market '{"description": "will india win world cup 2023?", "outcomes": ["YES", "NO"]}' --accountId userid.testnet
#near view userid.testnet get_markets '{"from_index":0, "limit": 1}'
#near call userid.testnet place_bet '{"market_id": 0, "prediction": "YES"}' --accountId userid.testnet --amount 0.1
#near call userid.testnet place_bet '{"market_id": 0, "prediction": "NO"}' --accountId userid.testnet --amount 1
#near call userid.testnet settle_market '{"market_id": 0, "winning_outcome": "YES"}' --accountId userid.testnet

