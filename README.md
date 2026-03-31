# TreasuryManager V2 — Market Cap Treasury Management

Smart contract and frontend for treasury management with market cap calculations, daily caps, cooldowns, TWAP circuit breaker, and 90-day emergency mode.

## Contract Details

- **Network:** Base (Chain ID: 8453)
- **Contract Address:** `0x24bB484cd9BF4663Aed2d0cdE5Bdc6E6D5bd38A4`
- **Owner:** `0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506`
- **Verified:** [Blockscout](https://base.blockscout.com/address/0x24bb484cd9bf4663aed2d0cde5bdc6e6d5bd38a4)

## Features

### Path 2 — Market Cap
- **Market Cap Calculation:** `(Total ETH Spent / Total Tokens Received) × 100B`
- **Weighted Average Cost:** Tracks total ETH spent and tokens received across all buybacks
- **Daily Caps:** Configurable per token per action type (BuybackWETH, BuybackUSDC, Burn, Stake, RebalanceWETH, RebalanceUSDC)
- **Daily Gas Limits:** Configurable per action type
- **Slippage Protection:** Built-in 3% slippage check
- **Cooldown:** 4 hours between actions
- **TWAP Circuit Breaker:** Blocks actions if spot price is >15% above 24h TWAP from Uniswap V3 pool

### Path 3 — 90-Day Emergency Mode
- **No ROI/market cap/TWAP checks** in emergency mode
- **Snapshot Balance:** Records token balance on first emergency trigger
- **Vesting:** 20% of snapshot balance vested over 5 days (4% per day)
- **Cumulative Tracking:** Total usage across all emergency calls tracked against allowance
- **Auto-Expiry:** Emergency mode automatically expires after 90 days
- **Owner Deactivation:** Owner can manually deactivate emergency mode

### Admin Controls
- Add/remove managed tokens
- Configure action daily caps and gas limits
- Set/update Uniswap V3 pool for TWAP
- Set operator address
- Withdraw ETH and tokens (owner only)

## Frontend

Interactive dashboard built with Scaffold-ETH 2:
- **Overview:** Token status, market caps, cooldowns, emergency status
- **Actions:** Execute treasury actions, record buybacks
- **Emergency:** Trigger/deactivate emergency mode, execute emergency actions
- **Admin:** Token management, operator settings, withdrawals

**Live App:** [IPFS](https://bafybeih7frvja52qekqb2j3kkvhkharyt3wbdfgunbqlffwytac5dzc2ea.ipfs.community.bgipfs.com/)

## Development

```bash
yarn install
yarn fork --network base     # Terminal 1
yarn deploy                  # Terminal 2
yarn start                   # Terminal 3
```

## Testing

```bash
cd packages/foundry
forge test -vvv              # 53 tests
```

## License

MIT
