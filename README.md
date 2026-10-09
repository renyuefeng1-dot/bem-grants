# BEM Task Escrow (bem-grants)

On-chain task settlement for BEM: a client locks BEM in the contract up front, a contractor delivers, M-of-N reviewers sign off and the contract settles automatically (with a small burn). Client withdrawals of unallocated funds need a 7-day on-chain notice. **BSC testnet demo, unaudited.**

- Demo: https://renyuefeng1-dot.github.io/bem-grants/
- 中文说明: [README_zh.md](README_zh.md)
- The contract keeps its original code name `GrantEscrow` (functions like `createMilestone`, `voteRelease`); only the UI wording changed.
