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
