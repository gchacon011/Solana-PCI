#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORKSPACE="$ROOT/solana-pci"
PROGRAM="$WORKSPACE/programs/solana-pci/src"

if [[ ! -f "$WORKSPACE/Anchor.toml" || ! -f "$PROGRAM/lib.rs" ]]; then
  echo "ERROR: Run this script from within the Solana-PCI Git repository; expected solana-pci/ Anchor workspace."
  exit 1
fi

mkdir -p "$PROGRAM/instructions"

cat > "$PROGRAM/constants.rs" <<'RUST'
use anchor_lang::prelude::*;

#[constant]
pub const COUNTER_SEED: &[u8] = b"counter";

#[constant]
pub const JOB_SEED: &[u8] = b"job";

#[constant]
pub const HELLO_WORLD_LAMPORTS: u64 = 1;

#[constant]
pub const MAX_COUNT: u64 = 10;
RUST

cat > "$PROGRAM/state.rs" <<'RUST'
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
RUST

cat > "$PROGRAM/error.rs" <<'RUST'
use anchor_lang::prelude::*;

#[error_code]
pub enum ErrorCode {
    #[msg("Only the counter authority can update this counter")]
    Unauthorized,
    #[msg("Counter has reached the maximum value")]
    CounterOverflow,
    #[msg("The job interval must be greater than zero")]
    InvalidInterval,
    #[msg("The first execution time cannot be in the past")]
    FirstRunInPast,
    #[msg("The job is not due yet")]
    JobNotDue,
    #[msg("The job is paused")]
    JobPaused,
    #[msg("The scheduled timestamp is outside the supported range")]
    TimestampOverflow,
    #[msg("The job execution counter overflowed")]
    ExecutionCounterOverflow,
}
RUST

cat > "$PROGRAM/instructions.rs" <<'RUST'
pub mod initialize;
pub mod increment;
pub mod create_job;
pub mod execute_job;
pub mod set_job_paused;

pub use initialize::*;
pub use increment::*;
pub use create_job::*;
pub use execute_job::*;
pub use set_job_paused::*;
RUST

cat > "$PROGRAM/instructions/create_job.rs" <<'RUST'
use anchor_lang::prelude::*;

use crate::{constants::JOB_SEED, error::ErrorCode, state::Job};

#[derive(Accounts)]
#[instruction(job_id: u64)]
pub struct CreateJob<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        init,
        payer = authority,
        space = 8 + Job::INIT_SPACE,
        seeds = [JOB_SEED, authority.key().as_ref(), &job_id.to_le_bytes()],
        bump
    )]
    pub job: Account<'info, Job>,
    pub system_program: Program<'info, System>,
}

pub fn handle_create_job(
    ctx: Context<CreateJob>,
    job_id: u64,
    interval_seconds: u64,
    first_run_at: i64,
) -> Result<()> {
    require!(interval_seconds > 0, ErrorCode::InvalidInterval);
    let interval_i64 = i64::try_from(interval_seconds)
        .map_err(|_| error!(ErrorCode::InvalidInterval))?;

    let now = Clock::get()?.unix_timestamp;
    require!(first_run_at >= now, ErrorCode::FirstRunInPast);

    // Ensure at least the first interval can be represented before accepting
    // a schedule that would otherwise fail on its first execution.
    first_run_at
        .checked_add(interval_i64)
        .ok_or_else(|| error!(ErrorCode::TimestampOverflow))?;

    let job = &mut ctx.accounts.job;
    job.authority = ctx.accounts.authority.key();
    job.job_id = job_id;
    job.interval_seconds = interval_seconds;
    job.next_run_at = first_run_at;
    job.last_run_at = 0;
    job.execution_count = 0;
    job.paused = false;
    job.bump = ctx.bumps.job;

    emit!(JobCreated {
        job: job.key(),
        authority: job.authority,
        job_id,
        interval_seconds,
        first_run_at,
    });
    Ok(())
}

#[event]
pub struct JobCreated {
    pub job: Pubkey,
    pub authority: Pubkey,
    pub job_id: u64,
    pub interval_seconds: u64,
    pub first_run_at: i64,
}
RUST

cat > "$PROGRAM/instructions/execute_job.rs" <<'RUST'
use anchor_lang::prelude::*;

use crate::{constants::JOB_SEED, error::ErrorCode, state::Job};

#[derive(Accounts)]
pub struct ExecuteJob<'info> {
    #[account(
        mut,
        seeds = [JOB_SEED, job.authority.as_ref(), &job.job_id.to_le_bytes()],
        bump = job.bump
    )]
    pub job: Account<'info, Job>,
    /// CHECK: The caller only pays for and authorizes the trigger transaction.
    /// The caller receives no authority over the job's stored configuration.
    pub caller: Signer<'info>,
}

pub fn handle_execute_job(ctx: Context<ExecuteJob>) -> Result<()> {
    let job = &mut ctx.accounts.job;
    require!(!job.paused, ErrorCode::JobPaused);

    let now = Clock::get()?.unix_timestamp;
    let scheduled_for = job.next_run_at;
    require!(now >= scheduled_for, ErrorCode::JobNotDue);

    let interval = i64::try_from(job.interval_seconds)
        .map_err(|_| error!(ErrorCode::InvalidInterval))?;
    let next_run_at = scheduled_for
        .checked_add(interval)
        .ok_or_else(|| error!(ErrorCode::TimestampOverflow))?;
    let execution_count = job.execution_count
        .checked_add(1)
        .ok_or_else(|| error!(ErrorCode::ExecutionCounterOverflow))?;

    // Fixed-cadence schedule: advance from the due timestamp, not from `now`.
    // A late worker can process missed periods one transaction at a time.
    // A committed transaction advances the checkpoint atomically, so replaying
    // the same trigger cannot record the same scheduled period twice.
    job.last_run_at = now;
    job.next_run_at = next_run_at;
    job.execution_count = execution_count;

    emit!(JobExecutionRecorded {
        job: job.key(),
        job_id: job.job_id,
        execution_number: execution_count,
        scheduled_for,
        executed_at: now,
        next_run_at,
        caller: ctx.accounts.caller.key(),
    });
    Ok(())
}

#[event]
pub struct JobExecutionRecorded {
    pub job: Pubkey,
    pub job_id: u64,
    pub execution_number: u64,
    pub scheduled_for: i64,
    pub executed_at: i64,
    pub next_run_at: i64,
    pub caller: Pubkey,
}
RUST

cat > "$PROGRAM/instructions/set_job_paused.rs" <<'RUST'
use anchor_lang::prelude::*;

use crate::{constants::JOB_SEED, state::Job};

#[derive(Accounts)]
pub struct SetJobPaused<'info> {
    pub authority: Signer<'info>,
    #[account(
        mut,
        has_one = authority,
        seeds = [JOB_SEED, authority.key().as_ref(), &job.job_id.to_le_bytes()],
        bump = job.bump
    )]
    pub job: Account<'info, Job>,
}

pub fn handle_set_job_paused(ctx: Context<SetJobPaused>, paused: bool) -> Result<()> {
    let job = &mut ctx.accounts.job;
    job.paused = paused;

    emit!(JobPauseChanged {
        job: job.key(),
        job_id: job.job_id,
        authority: ctx.accounts.authority.key(),
        paused,
    });
    Ok(())
}

#[event]
pub struct JobPauseChanged {
    pub job: Pubkey,
    pub job_id: u64,
    pub authority: Pubkey,
    pub paused: bool,
}
RUST

cat > "$PROGRAM/lib.rs" <<'RUST'
pub mod constants;
pub mod error;
pub mod instructions;
pub mod state;

use anchor_lang::prelude::*;

pub use constants::*;
pub use instructions::*;
pub use state::*;

declare_id!("GRT9XiR764J2b6HygvgrmjEN7cJH9d8RRFKr1uJG4cLX");

#[program]
pub mod solana_pci {
    use super::*;

    // Retained starter instructions; remove them after the PCI program has
    // replaced the counter scaffold and the migration is tested.
    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        crate::instructions::initialize::handle_initialize(ctx)
    }

    pub fn increment(ctx: Context<Increment>) -> Result<()> {
        crate::instructions::increment::handle_increment(ctx)
    }

    pub fn create_job(
        ctx: Context<CreateJob>,
        job_id: u64,
        interval_seconds: u64,
        first_run_at: i64,
    ) -> Result<()> {
        crate::instructions::create_job::handle_create_job(
            ctx,
            job_id,
            interval_seconds,
            first_run_at,
        )
    }

    pub fn execute_job(ctx: Context<ExecuteJob>) -> Result<()> {
        crate::instructions::execute_job::handle_execute_job(ctx)
    }

    pub fn set_job_paused(ctx: Context<SetJobPaused>, paused: bool) -> Result<()> {
        crate::instructions::set_job_paused::handle_set_job_paused(ctx, paused)
    }
}
RUST

cd "$WORKSPACE"
echo "== Rust formatting =="
cargo fmt --all -- --check || cargo fmt --all

echo "== Anchor build =="
anchor build

echo "== Rust workspace tests =="
cargo test --workspace

echo ""
echo "Milestone 1 source files have been applied and the build/test commands completed."
echo "Review changes with: git -C '$ROOT' status --short"
echo "No commit or push was performed by this script."
