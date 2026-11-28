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
    let interval_i64 =
        i64::try_from(interval_seconds).map_err(|_| error!(ErrorCode::InvalidInterval))?;

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
