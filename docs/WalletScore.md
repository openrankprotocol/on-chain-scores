# WalletScore

Multi-domain wallet score registry with competitive bidding for score publication.

## Overview

WalletScore is an on-chain registry for wallet reputation scores across multiple domains (apps). Score publishers compete via a bidding mechanism to fulfill score requests, with economic incentives enforced through bonds and slashing.

**Key Features:**
- Multiple score domains (Avici, Uniswap, etc.)
- Score sets as timestamped snapshots
- Publisher registry with portable IDs (address-independent)
- Competitive bidding with slashing for non-fulfillment
- Trust-based verification (TEE + merkle proofs planned)

## Concepts

### Domains

A domain represents an app or context for which scores are calculated (e.g., Avici, Uniswap). Each domain has:
- A unique `DomainId` (bytes32, typically `keccak256(name)`)
- Metadata URI pointing to JSON with name, description, author, docs URL

Domains are registered by admins and define the scope within which scores are meaningful.

### Publishers

Publishers are entities authorized to calculate and publish scores. Each publisher has:
- A unique `PublisherId` (auto-incrementing uint256)
- A current address (can be migrated without losing identity)
- Metadata URI
- Active/inactive status
- Denylist expiration (for failed fulfillments)
- Bond balance

Publisher IDs are portable—if a publisher needs to change their address (key rotation, multisig migration), they retain their identity and reputation.

### Score Sets

A score set is a snapshot of scores for wallets in a domain at a specific timestamp. Score sets:
- Belong to a single domain
- Have a score timestamp (when scores were calculated)
- Contain ranked entries (wallet address + score)
- Progress through Draft → Published states
- Are immutable once published

### Requests

Users who need scores create requests specifying:
- Domain
- Wallets (specific addresses) or rank range
- Acceptable score timestamp window
- Quoting deadline (when bids must arrive)
- Fulfillment deadline (when scores must be delivered)
- Maximum budget (deposited with request)
- Selection mode (cheapest or fastest)

### Bids

Publishers submit bids on requests, specifying:
- Price (must be ≤ maxBudget)
- Promised duration (time needed after selection)

Bids are validated against:
- Quoting deadline not passed
- Publisher not denylisted
- Publisher has sufficient bond
- `quotingDeadline + promisedDuration < fulfillmentDeadline`

## Architecture

### User-Defined Types

```solidity
type DomainId is bytes32;      // Domain identifier
type ScoreSetId is uint256;    // Score set ID (0 = not found)
type RequestId is uint256;     // Request ID
type PublisherId is uint256;   // Publisher ID
type BidId is uint256;         // Bid ID
```

### Contracts

| File | Description |
|------|-------------|
| `Types.sol` | UDTs, enums, and structs |
| `IWalletScore.sol` | Interface with events, errors, function signatures |
| `WalletScoreV1.sol` | UUPS-upgradeable implementation |

### Roles (AccessControl)

| Role | Capabilities |
|------|--------------|
| `DEFAULT_ADMIN_ROLE` | Register domains/publishers, configure parameters, withdraw treasury |
| `PUBLISHER_ROLE` | Create/publish score sets, submit bids, fulfill requests |

## Workflows

### Score Set Publication (No Request)

Publishers can proactively publish score sets:

```
1. createScoreSet(domainId, scoreTimestamp) → ScoreSetId
2. addScoresToScoreSet(id, startRank, entries[])  // repeatable
3. publishScoreSet(id)  // finalizes, immutable
```

### Request-Bid-Fulfill Workflow

```
┌─────────────┐
│   QUOTING   │◄── createRequest() with deposit
└──────┬──────┘
       │ quotingDeadline passes
       ▼
┌─────────────┐
│  SELECTING  │◄── advanceRequest() selects winner
└──────┬──────┘
       │ winner selected
       ▼
┌─────────────┐
│  ASSIGNED   │◄── publisher has promisedDuration to fulfill
└──────┬──────┘
       │
       ├─── fulfillRequest() ───► FULFILLED (payout + refund)
       │
       └─── deadline expires ───► advanceRequest()
                                      │
                                      ├── slash + denylist
                                      ├── select next bidder → ASSIGNED
                                      └── no valid bidders → FAILED (refund)
```

### State Transitions

| From | Event | To |
|------|-------|-----|
| Quoting | `quotingDeadline` passes | Selecting |
| Quoting | `cancelRequest()` | Cancelled |
| Selecting | Valid bidder found | Assigned |
| Selecting | No valid bidders | Failed |
| Selecting | `cancelRequest()` | Cancelled |
| Assigned | `fulfillRequest()` succeeds | Fulfilled |
| Assigned | Bidder deadline expires | Selecting (slash + try next) |

## Bond System

### Publisher Bonds

Publishers must maintain a minimum bond to participate in bidding:

```solidity
depositBond()           // Add to bond balance
withdrawBond(amount)    // Requires no active bids, maintains minimum
```

**Constraints:**
- Cannot submit bids if bond < `minPublisherBond`
- Cannot withdraw if active bids exist
- Partial withdrawal must leave ≥ `minPublisherBond`

### Slashing

When a bidder fails to fulfill within their promised duration:

1. **Slash amount**: 50% of the bid price (capped at bond balance)
2. **Bond deducted** from failed publisher
3. **Denylist applied** based on lost opportunities

### Slash Distribution

**With lost bidders** (bidders who were valid when failed bidder was selected but are now invalid):

| Recipient | Share | Notes |
|-----------|-------|-------|
| Treasury | 20% | Protocol revenue |
| Lost bidders | 50% | Proportional to quoted price, credited to bond |
| Next bidder | 30% | Incentive to step up |

**Without lost bidders**:

| Recipient | Share |
|-----------|-------|
| Treasury | 40% |
| Next bidder / requester | 60% |

### Denylist Duration

```
duration = baseDenylistDuration
         + (lostBidderCount × denylistPerLostBidder)
         + (totalLostValue ÷ denylistValueDivisor)
```

Default parameters:
- `baseDenylistDuration`: 1 day
- `denylistPerLostBidder`: 1 hour
- `denylistValueDivisor`: 1 ether (1 hour per ether of lost value)

## Events

### Domain Events
- `DomainRegistered(domainId, metadataUri)`
- `DomainMetadataUpdated(domainId, metadataUri)`

### Publisher Events
- `PublisherRegistered(publisherId, addr, metadataUri)`
- `PublisherAddressUpdated(publisherId, oldAddr, newAddr)`
- `PublisherMetadataUpdated(publisherId, metadataUri)`
- `PublisherDeactivated(publisherId)`
- `PublisherDenylisted(publisherId, until)`

### Score Set Events
- `ScoreSetCreated(scoreSetId, domainId, publisher)`
- `ScoreSetPublished(scoreSetId, entryCount, minRank, maxRank)`

### Bidding Events
- `RequestCreated(requestId, requester, domainId, maxBudget)`
- `BidSubmitted(bidId, requestId, publisher, price, promisedDuration)`
- `BidSelected(requestId, bidId, publisher)`
- `RequestFulfilled(requestId, scoreSetId, publisher, payout)`
- `BidderFailed(requestId, bidId, publisher, slashAmount, denylistUntil)`
- `RequestFailed(requestId)`
- `RequestCancelled(requestId)`

### Bond Events
- `BondDeposited(publisher, amount, newBalance)`
- `BondWithdrawn(publisher, amount, newBalance)`
- `SlashDistributed(requestId, toTreasury, toLostBidders, toNextOrRequester)`

## Query Functions

### Domain Queries
- `getDomainMetadataUri(domainId)` → metadata URI

### Publisher Queries
- `getPublisher(publisherId)` → Publisher struct
- `getPublisherByAddress(addr)` → (PublisherId, Publisher)
- `getPublisherBond(publisherId)` → bond balance

### Score Set Queries
- `getScoreSetMeta(scoreSetId)` → ScoreSetMeta
- `getRankAndScore(scoreSetId, wallet)` → (rank, score)
- `getRanksAndScores(scoreSetId, wallets[])` → (ranks[], scores[])
- `getEntryAtRank(scoreSetId, rank)` → Entry
- `getEntriesInRankRange(scoreSetId, startRank, count)` → Entry[]
- `getLatestScoreSetId(domainId, minTs, maxTs)` → ScoreSetId

### Request/Bid Queries
- `getRequest(requestId)` → ScoreRequest
- `getBid(bidId)` → Bid
- `getRequestBids(requestId)` → BidId[]

### System Queries
- `getTreasuryBalance()` → balance
- `getMinPublisherBond()` → minimum bond
- `getDenylistParams()` → (baseDuration, perLostBidder, valueDivisor)
- `getWithdrawable(addr)` → withdrawable balance

## Deployment

### Environment Variables

```bash
DEPLOYER_PRIVATE_KEY=0x...
WALLETSCORE_PROXY_CONTRACT_ADDRESS=  # empty for fresh deploy, address for upgrade
```

### Deploy Script

```bash
# Fresh deployment
forge script script/WalletScore.s.sol --rpc-url <RPC_URL> --broadcast

# Upgrade existing proxy
WALLETSCORE_PROXY_CONTRACT_ADDRESS=0x... forge script script/WalletScore.s.sol --rpc-url <RPC_URL> --broadcast
```

### Post-Deployment Setup

1. Set minimum publisher bond:
   ```solidity
   setMinPublisherBond(0.1 ether)
   ```

2. Register domains:
   ```solidity
   registerDomain(keccak256("avici"), "ipfs://...")
   ```

3. Register publishers:
   ```solidity
   registerPublisher(publisherAddress, "ipfs://...")
   ```

## Future Enhancements

- **TEE Attestation**: EigenCompute/EigenCloud integration for verified computation
- **Merkle Proofs**: On-chain verification of individual scores via `merkleRoot` in ScoreSetMeta
- **Stake-weighted Reputation**: Publisher reputation affecting bid selection
- **Dynamic Slash Rates**: Configurable slash percentages based on severity
