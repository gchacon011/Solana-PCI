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

Distinguish transaction submission from confirmation and finalization. Classify failures, apply bounded retries with backoff where appropriate, and alert on persistent failures rather than retrying indefinitely.

4. Secure transaction signing

Protect signing authority and secrets. Use least-privilege key management, isolate signing responsibilities where possible, and never embed private keys in source code, logs, or ordinary configuration files.

5. Realistic timing guarantees

Cron schedules are triggers, not guarantees of exact execution time. Network congestion, RPC availability, worker downtime, and transaction confirmation affect when work actually executes. Programs should validate time windows and state using on-chain data when timing is security- or value-critical.

6. Observability and auditability

Record the job definition, expected execution time, attempt count, transaction signature, confirmation status, and final outcome or program error.

Conceptual Architecture

Cron Scheduler / Job Queue
          |
                    v
                    Job Worker + Eligibility Checks
                              |
                                        v
                                        Secure Transaction Signer
                                                  |
                                                            v
                                                            Solana RPC Provider
                                                                      |
                                                                                v
                                                                                Solana Transaction
                                                                                          |
                                                                                                    v
                                                                                                    On-chain Program
                                                                                                      - validates authority and accounts
                                                                                                        - checks time and job state
                                                                                                          - prevents duplicate execution
                                                                                                            - applies the state transition
                                                                                                                      |
                                                                                                                                v
                                                                                                                                Confirmation Monitor
                                                                                                                                          |
                                                                                                                                                    v
                                                                                                                                                    Logs / Metrics / Alerts

                                                                                                                                                    Initial Implementation Roadmap

                                                                                                                                                    1. Define supported job types, schedule semantics, and the job lifecycle.
                                                                                                                                                    2. Select the scheduler and job-queue approach.
                                                                                                                                                    3. Define RPC-provider and secure-signing requirements.
                                                                                                                                                    4. Specify on-chain validation, job state, and idempotency rules.
                                                                                                                                                    5. Build a minimal end-to-end scheduled transaction on Solana Devnet.
                                                                                                                                                    6. Add confirmation tracking, retries, monitoring, alerting, and audit logs.
                                                                                                                                                    7. Test normal execution, duplicate submissions, delayed confirmation, worker restarts, and failure recovery.
                                                                                                                                                    8. Document deployment, operations, and security assumptions.

                                                                                                                                                    Project Status

                                                                                                                                                    This repository is the starting point for the Solana PCI implementation. Architecture and implementation details will be refined as the project develops.

                                                                                                                                                    Security notice: This project is under development and is not represented as audited or production-ready. Do not use it to control production funds or critical operations until it has undergone appropriate security review, testing, and operational hardening.

                                                                                                                                                    Terminology

                                                                                                                                                    - PCI: Primary Cron Implementation.
                                                                                                                                                    - Scheduler: Off-chain service that determines when a job should be attempted.
                                                                                                                                                    - Worker: Component that prepares and submits the transaction for a due job.
                                                                                                                                                    - Keeper / Automation: An external actor or network that triggers on-chain execution.
                                                                                                                                                    - Idempotency: A property ensuring repeated attempts do not apply the same logical operation more than once.