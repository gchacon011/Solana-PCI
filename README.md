README.md

Solana PCI — Primary Cron Implementation

Solana PCI (Primary Cron Implementation) explores reliable scheduled execution for Solana applications: coordinating time-based and recurring workflows off-chain, then executing them safely through Solana transactions and on-chain programs.

Why Cron Jobs Matter in Solana Development

Solana programs are transaction-driven. A deployed program does not continuously run in the background, wake itself at a scheduled time, or independently submit transactions. An instruction executes only when a transaction invokes the program.

Scheduled execution is therefore an important building block for applications that need recurring or time-dependent behavior, including:

- Distributing rewards, incentives, or recurring payments.
- Executing settlements, auctions, subscriptions, and renewals.
- Releasing time-locked assets or advancing scheduled protocol stages.
- Running periodic checkpoints, maintenance, or state transitions.
- Coordinating off-chain services with on-chain program logic.

A typical design combines an off-chain scheduler or automation network with an on-chain program:

1. A scheduler or keeper monitors a schedule and identifies work that may be due.
2. A worker checks eligibility and prepares the required instruction.
3. A transaction is signed and submitted through a Solana RPC endpoint.
4. The on-chain program independently validates the request and current state.
5. The transaction is confirmed, and monitoring records its outcome.

The Solana Clock sysvar provides on-chain time and slot information that programs can inspect during instruction execution. It does not wake a program, schedule a transaction, or guarantee execution at an exact wall-clock instant.

Core Design Principles

1. On-chain validation is authoritative

The scheduler is an execution trigger, not a source of trust. The program must validate relevant accounts, authority, timing conditions, and job state before applying any state transition.

2. Idempotent execution

Scheduled work may be submitted more than once because of retries, network failures, or uncertain confirmation status. The program should prevent duplicate effects using mechanisms such as unique job identifiers, sequence numbers, processed-period markers, and guarded job-state transitions.

3. Reliable failure handling

Distinguish transaction submission from confirmation and finalization. Classify failures, apply bounded retries with backoff where appropriate, and alert on persistent failures rather than retrying indefinitely
