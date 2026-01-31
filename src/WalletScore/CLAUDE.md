# WalletScore

Let's create a wallet score publishing system in EVM.

We (initially, but eventually anyone) have scores calculated based on wallets and their activities.
Scores are bound to specific score domain bound to activity types ("apps"),
e.g., Avici, Uniswap, etc.
We own the score formula and calculate the scores offchain, then publish them upon request.
Essentially, the smart contracts will be a registry of scores, indexed by app types and wallets.

## Concepts

### Score Domains

Bound to the app the user uses, e.g., Avici, Uniswap, etc.
A user may use different apps, and may have different reputation scores in corresponding domains.

### Scores

Plain uint256.  Its interpretation is up to the score developer.
The documentation of each domain will specify the interpretation.

### Score Sets

For some domains, scores are calculated wholesale for a network of users.
This is called a score set.  A score set is essentially a snapshot of scores for a given time.

### Score Timestamp

A score value is calculated with the up-to-date information available at the time of calculation.
This is called a score timestamp.  Score timestamps are bound to individual scores.
If a score is from a score set, the score timestamp is inherited from the score set.o

## Workflow

Those who wish to utilize scores request them.  Request patterns include:

* Scores for a list of wallets in all app domains
* Scores for a list of wallets in a list of app domains
* Rank m..n scores in a score set, e.g. rank 0-99, 100-199, etc.

All of these queries include the score timestamp window.  Latest scores in this window are returned.
The window mechanism is intended to allow for reuse of slightly stale scores.  Conceptually, the
lookup workflow is:

1. Give me the latest score set ID, one for each of these domains, for this time window.
2. Give me the scores of these wallets in this score set.
   -- or --
   Give me the m..n rankings in this score set.

If #1 returns no score set, there's a request phase before #2:

1. The user requests: "Publish the scores of these wallets in these domains, as of this timestamp
   window."  This records the request on chain and emits an event.
2. Provider sees the event, uploads a score set that covers the request (note: it may contain
   more wallets than requested, and the timestamp may not be the upper bound of the window).
   This also emits an event.
3. The user sees the event and queries again.