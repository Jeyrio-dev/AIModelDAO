# AIModelDAO

A decentralized autonomous organization for collectively governing AI model development and funding decisions.

## Features

- **Proposal Creation**: Community members can create proposals for AI model parameters, funding, and governance decisions
- **Token-Based Voting**: Voting power is proportional to DAO token holdings
- **Transparent Governance**: All proposals and votes are recorded on-chain
- **Token Transfer**: Members can transfer governance tokens to other participants

## Contract Functions

### Public Functions
- `initialize()` - Initialize the contract with initial token distribution
- `create-proposal(title, description, duration)` - Create a new governance proposal
- `vote(proposal-id, vote-for)` - Vote on an active proposal
- `transfer-tokens(recipient, amount)` - Transfer governance tokens

### Read-Only Functions
- `get-proposal(proposal-id)` - Retrieve proposal details
- `get-token-balance(holder)` - Check token balance for an address

## Usage

1. Deploy the contract and call `initialize()`
2. Create proposals using `create-proposal`
3. Token holders vote using the `vote` function
4. Monitor proposal outcomes through `get-proposal`

## Testing

Run tests using Clarinet:
```bash
clarinet test