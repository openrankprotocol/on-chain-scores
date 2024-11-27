# OnChainScores Smart Contract

1. **Simulate Deployment**
   ```sh
   forge script script/OnChainScores.s.sol
   ```
   - This simulation provides deployment guarantees and gas cost estimates.
   - **Note**: Ensure the `.env` file is present.

2. **Deploy to Testnet/Localnet**
   - To deploy on a different network (e.g., `Ethereum mainnet`), adjust the `rpc-url` accordingly.
   ```sh
   forge script script/OnChainScores.s.sol --rpc-url https://rpc-amoy.polygon.technology/ --broadcast --optimize --optimizer-runs 4000
   ```

   To deploy on `anvil` localnet, use this one.
   ```sh
   forge script script/OnChainScores.s.sol --rpc-url http://localhost:8545 --broadcast --optimize --optimizer-runs 4000
   ```
