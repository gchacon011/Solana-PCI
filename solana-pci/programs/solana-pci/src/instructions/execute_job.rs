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

    let interval =
        i64::try_from(job.interval_seconds).map_err(|_| error!(ErrorCode::InvalidInterval))?;
    let next_run_at = scheduled_for
        .checked_add(interval)
        .ok_or_else(|| error!(ErrorCode::TimestampOverflow))?;
    let execution_count = job
        .execution_count
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
