# On-Chain Scores

**Bringing off-chain reputation and ranking data on-chain for composable, trustless access.**

## Problem Statement

Reputation and ranking systems (OpenRank scores, developer rankings, social graph metrics) are typically computed off-chain, making them inaccessible to smart contracts. This creates a gap where:

- **DeFi protocols** cannot gate access based on user reputation
- **DAOs** cannot weight votes by contributor scores
- **NFT projects** cannot implement reputation-based minting
- **Airdrops** cannot use sophisticated eligibility criteria beyond simple token holdings

There's no standard way to bring these scores on-chain in a verifiable, efficient manner that other contracts can easily consume.

## Solution

On-Chain Scores provides a suite of smart contracts that:

1. **Store reputation data on-chain** - Leaderboards with scores sorted by rank for efficient querying
2. **Enable composability** - Other smart contracts can read scores directly via interfaces
3. **Support multiple domains** - Farcaster OpenRank, GitHub DevRank, and extensible to any reputation system
4. **Provide a marketplace for scores** - Publishers compete to fulfill score requests with economic incentives via WalletScore

## Core Smart Contracts

### 1. OnChainScoresV2 (Farcaster OpenRank)

**Purpose:** Stores global Farcaster OpenRank scores on-chain, enabling smart contracts to query a user's social reputation.

**How it works:**
- Maintains a sorted leaderboard of `(FID, score)` entries
- Scores are scaled to use full uint256 range: `[0.0, 1.0)` maps to `[0, 2^256)`
- Supports both FID-based queries and Ethereum address lookups via Neynar's verification contract
- Owner appends scores in descending order; can truncate to update

**Key Functions:**
- `getRankAndScoreForFID(fid)` - Get a Farcaster user's rank and score
- `getFIDRankAndScoreForVerifier(address)` - Look up by Ethereum address
- `getUsersInRankRange(start, count)` - Get top N users
- `appendScores(users[])` / `truncate(count)` - Admin functions to update leaderboard

**Example Use Case:**
```solidity
contract GatedMint {
    IFarcasterOpenRank openRank;
    
    function mint() external {
        (, uint256 rank,) = openRank.getFIDRankAndScoreForVerifier(msg.sender);
        require(rank >= 1 && rank <= 1000, "Must be top 1000");
        // ... mint NFT
    }
}
```

### 2. DevRankV1 (GitHub Developer Scores)

**Purpose:** Stores OpenRank scores for GitHub developers, enabling on-chain verification of developer reputation.

**How it works:**
- Similar architecture to Farcaster scores but keyed by GitHub username (string)
- Maintains sorted leaderboard with `(username, score)` entries
- Useful for developer-focused protocols, grants, and contributor rewards

**Key Functions:**
- `getRankAndScoreForUser(username)` - Get a developer's rank and score
- `getUsersInRankRange(start, count)` - Get top developers
- `getRanksAndScoresForUsers(usernames[])` - Batch lookup

### 3. WalletScoreV1 (Multi-Domain Score Registry)

**Purpose:** A comprehensive system for managing wallet scores across multiple domains with a competitive marketplace for score publication.

**How it works:**

#### Domains
- Each domain (e.g., "avici", "uniswap") represents a context for scores
- Domains have metadata URIs pointing to JSON descriptions
- Admin-registered with unique `DomainId` (typically `keccak256(name)`)

#### Publishers
- Entities authorized to calculate and publish scores
- Have portable IDs (can migrate addresses without losing identity)
- Must maintain a bond to participate in bidding
- Can be denylisted for failed fulfillments

#### Score Sets
- Timestamped snapshots of wallet scores for a domain
- Created as drafts, populated with entries, then published
- Immutable once published
- Include merkle root for future verification

#### Request-Bid-Fulfill Workflow
```
User creates request ──► Publishers submit bids ──► Winner selected ──► Fulfillment
       │                        │                         │                  │
       ▼                        ▼                         ▼                  ▼
   Deposit ETH            Quote price &            Cheapest/fastest      Provide score
                          duration                  wins                  set, get paid
```

#### Economic Incentives
- **Bonds:** Publishers deposit ETH as collateral
- **Slashing:** Failed fulfillment = 50% of bid price slashed
- **Denylist:** Failed publishers banned from bidding temporarily
- **Distribution:** Slashed funds go to treasury, lost bidders, and next bidder

**Key Functions:**
- `createRequest(...)` - Request scores for wallets/ranks with deposit
- `submitBid(requestId, price, duration)` - Publishers bid on requests
- `fulfillRequest(requestId, scoreSetId)` - Winner delivers scores
- `getRankAndScore(scoreSetId, wallet)` - Query published scores

### 4. Interfaces

| Interface | Purpose |
|-----------|---------|
| `IFarcasterOpenRank` | Standard interface for Farcaster score queries |
| `IDevRank` | Standard interface for GitHub developer score queries |
| `IWalletScore` | Full interface for the WalletScore registry |
| `IVerificationsV4Reader` | Neynar's contract for ETH address ↔ FID mapping |

### 5. FarcasterOpenRankExample

**Purpose:** Demonstrates how to integrate Farcaster scores into your own contracts.

```solidity
function isTop100(address verifier) external view returns (bool) {
    (, uint256 rank,) = farcasterOpenRank.getFIDRankAndScoreForVerifier(verifier);
    return rank >= 1 && rank <= 100;
}
```

## Contract Upgrade Path

All core contracts use the UUPS (Universal Upgradeable Proxy Standard) pattern:

```
OnChainScores (V0) → OnChainScoresV1 → OnChainScoresV2
                          ↑                    ↑
                     Added batch          Added address
                     queries              lookups via FID
```

## Deployment

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- `.env` file with `DEPLOYER_PRIVATE_KEY`

### Simulate Deployment

```sh
forge script script/OnChainScores.s.sol
```

### Deploy to Network

```sh
# Polygon Amoy testnet
forge script script/OnChainScores.s.sol \
    --rpc-url https://rpc-amoy.polygon.technology/ \
    --broadcast \
    --optimize \
    --optimizer-runs 4000

# Local Anvil
forge script script/OnChainScores.s.sol \
    --rpc-url http://localhost:8545 \
    --broadcast \
    --optimize \
    --optimizer-runs 4000
```

### Deploy WalletScore

```sh
# Fresh deployment
forge script script/WalletScore.s.sol --rpc-url <RPC_URL> --broadcast

# Upgrade existing proxy
WALLETSCORE_PROXY_CONTRACT_ADDRESS=0x... \
    forge script script/WalletScore.s.sol --rpc-url <RPC_URL> --broadcast
```

## Development

### Build

```sh
forge build
```

### Test

```sh
forge test
```

### Format

```sh
forge fmt
```

## Documentation

- [WalletScore Deep Dive](docs/WalletScore.md) - Comprehensive documentation of the WalletScore system

## License

MIT
