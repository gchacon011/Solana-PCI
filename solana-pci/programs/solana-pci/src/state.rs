use anchor_lang::prelude::*;

#[account]
#[derive(InitSpace)]
pub struct Counter {
    pub count: u64,
    pub authority: Pubkey,
}

/// Authoritative on-chain state for one recurring PCI job.
///
/// The off-chain scheduler only triggers transactions. The program validates
/// timing and state transitions against this account before recording a run.
#[account]
#[derive(InitSpace)]
pub struct Job {
    pub authority: Pubkey,
    pub job_id: u64,
    pub interval_seconds: u64,
    pub next_run_at: i64,
    pub last_run_at: i64,
    pub execution_count: u64,
    pub paused: bool,
    pub bump: u8,
}
