# Solana PCI — Primary Cron Implementation

Solana PCI (Primary Cron Implementation) is an Anchor-based project to explore reliable scheduled execution for Solana applications. The intended design combines an off-chain scheduler or automation worker with an on-chain Solana program that validates and records scheduled operations.

> **Project status:** Early development. The repository currently contains the generated Anchor counter starter program and its initialization test. The PCI job registry, scheduled execution instructions, off-chain cron worker, and Devnet deployment are planned work; they are not implemented yet.

## Why scheduled execution matters on Solana

Solana programs are transaction-driven. A deployed program does not remain running in the background, wake itself at a specified time, or submit transactions independently. An instruction runs only when a transaction invokes the program.

Applications that need recurring or time-dependent behavior therefore need an external trigger, such as a cron service, keeper, or automation network. Potential use cases include:

- Distributing recurring rewards or incentives.
- Triggering settlements, auctions, subscription renewals, or other periodic protocol actions.
- Advancing scheduled stages or releasing time-locked assets.
- Running periodic checkpoints and maintenance operations.
- Coordinating off-chain services with on-chain program state.

The Solana Clock sysvar provides timestamp and slot information that a program can inspect while an instruction is executing. It does not wake a program or submit a transaction, and it does not guarantee execution at an exact wall-clock instant.

## Intended architecture

The target architecture separates transaction triggering from execution authority:

1. **Scheduler / keeper:** Watches job schedules and identifies jobs that may be due.
2. **Worker:** Loads job data, checks whether a trigger should be attempted, and prepares the instruction.
3. **Transaction submission:** Signs and submits a transaction to a Solana RPC endpoint.
4. **On-chain program:** Revalidates the job state, timing, and required authority. The scheduler is not trusted to enforce protocol rules.
5. **Confirmation monitor:** Tracks transaction signatures, confirmation outcomes, failures, and retries.

The on-chain program is intended to remain authoritative for job state and execution eligibility. Off-chain timing is a trigger, not a security boundary.

## Design principles

### On-chain validation

The program must validate the job account, authority, active status, timing conditions, and state transition before accepting an execution. Never rely solely on a worker's claim that a job is due.

### Idempotency

Retries and uncertain transaction confirmation can cause the same trigger to be submitted more than once. The planned job state will include an execution checkpoint (such as a sequence number and next-run timestamp) so that a committed execution cannot be applied again for the same schedule period.

### Failure handling

The worker should distinguish transaction submission from confirmation and finalization, classify failures, use bounded retries with backoff where appropriate, and alert on persistent failures.

### Secure signing

Keep private keys and wallet keypairs out of source control, logs, and ordinary configuration. Use least-privilege signing authority and secure secret management for any worker that submits transactions.

### Timing expectations

Cron schedules are best-effort triggers, not exact execution guarantees. RPC availability, worker uptime, network congestion, and transaction confirmation affect actual execution time. Use on-chain time and state checks where timing is security- or value-critical.

### Observability

The planned worker should record job identifiers, expected run times, attempt counts, transaction signatures, confirmation status, and final outcomes or program errors.

## Repository layout

The Anchor workspace is in the `solana-pci/` subdirectory:

```text
Solana-PCI/
├── README.md
└── solana-pci/
    ├── Anchor.toml
    ├── Cargo.toml
    ├── Cargo.lock
    ├── rust-toolchain.toml
    └── programs/
        └── solana-pci/
            ├── Cargo.toml
            ├── src/
            │   ├── constants.rs
            │   ├── error.rs
            │   ├── instructions.rs
            │   ├── instructions/
            │   │   ├── initialize.rs
            │   │   └── increment.rs
            │   ├── lib.rs
            │   └── state.rs
            └── tests/
                └── test_initialize.rs
```

Build artifacts are generated under the Anchor workspace's `target/` directory and should not be committed. Wallet keypairs, private keys, and `.env` files must never be committed.

## Current starter program

The currently committed program is the Anchor counter example, not the PCI cron engine:

- `initialize` creates the counter PDA using the `counter` seed and records its authority.
- `increment` allows the recorded authority to increment the counter, subject to the starter program's maximum count.
- `test_initialize.rs` exercises counter initialization and incrementing with LiteSVM.

These instructions are scaffolding for development and do not provide scheduled job functionality.

## Program configuration

- **Program name:** `solana_pci`
- **Program ID:** `GRT9XiR764J2b6HygvgrmjEN7cJH9d8RRFKr1uJG4cLX`
- **Anchor workspace:** `solana-pci/`
- **Configured provider cluster:** `localnet`
- **Configured wallet path:** `~/.config/solana/id.json`

The configured cluster is currently localnet. This repository does not claim that the program has been deployed to Devnet or Mainnet.

## Development environment

The workspace pins Rust through `rust-toolchain.toml` and declares Anchor Lang `1.2.2` in the program crate. Install the Rust toolchain, Solana/Agave CLI, SBF build tools, and a compatible Anchor CLI/AVM version before building.

From the repository root:

```bash
cd solana-pci
rustc --version
cargo --version
solana --version
anchor --version
```

Build the program:

```bash
anchor build
```

Run the Rust workspace tests:

```bash
cargo test --workspace
```

The current committed test is for the counter starter instructions. It is not yet a test suite for PCI job scheduling.

## Implementation roadmap

The following items are planned and should be marked complete only after their code is committed and tested:

1. **Job state and registration:** Define a Job account/PDA, authority, unique job identifier, interval, next-run timestamp, execution counter, and pause status. Implement validated job creation.
2. **Scheduled execution:** Add an instruction that checks the on-chain clock, rejects early or paused jobs, and advances the execution checkpoint atomically.
3. **Job administration:** Add authority-controlled pause and resume operations.
4. **Automated program tests:** Cover job creation, invalid intervals, past timestamps, unauthorized administration, not-yet-due execution, successful execution, duplicate triggers, and pause/resume behavior.
5. **Off-chain cron worker:** Discover due jobs, submit transactions, track signatures and confirmations, retry safely, and expose logs/metrics/alerts.
6. **Devnet end-to-end validation:** Deploy the program, execute a scheduled job through the worker, and document observed behavior and operational limits.
7. **Security review and hardening:** Review account constraints, signer permissions, replay/duplicate behavior, key management, denial-of-service risks, and failure recovery before any production use.

## Security notice

This project is under development and has not been represented as audited or production-ready. Do not use it to control production funds or critical operations. Complete testing, independent security review, and operational hardening before any Mainnet deployment.

## Terminology

- **PCI:** Primary Cron Implementation.
- **Scheduler / keeper:** An off-chain service or actor that triggers an attempt to execute a due job.
- **Worker:** The off-chain component that prepares, submits, and monitors transactions.
- **Job PDA:** The planned program-derived account holding a job's authoritative state.
- **Idempotency:** Ensuring repeated transaction attempts do not apply the same logical scheduled operation more than once.
