# Insurance Smart Contract

A Clarity smart contract implementing a basic insurance system with premium calculations and payouts.

## Core Features

- **Premium Management**: 10% fixed premium rate
- **Policy System**: Tracks individual policies with unique IDs
- **Payout System**: Secure fund distribution to policyholders

## Key Functions

### Public Functions
- `buy-policy`: Purchase new insurance policy
- `trigger-payout`: Process insurance claims

### Read-Only Functions
- `get-premium-for`: Calculate premium for given payout amount
- `get-pool-balance`: View total funds in pool
- `get-policy`: Retrieve policy details
- `get-contract-balance`: Check contract's STX balance
- `is-policy-active`: Verify policy status

## Safety Features

- Overflow protection for arithmetic operations
- Comprehensive input validation
- Balance checks before payouts
- Policy status verification

## Constants

- Maximum payout: 1,000,000,000,000 microSTX
- Minimum payout: 1,000,000 microSTX
- Maximum policy ID: 4,294,967,295

## Error Handling

- Policy not found: Error 1
- Insufficient funds: Error 2
- Inactive policy: Error 3
- Invalid amount: Error 4
- Insufficient pool funds: Error 5
- Arithmetic overflow: Error 6
- Invalid policy ID: Error 7

## Data Storage

- Pool balance tracking
- Policy mapping with holder details
- Sequential policy ID system
