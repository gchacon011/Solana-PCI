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
