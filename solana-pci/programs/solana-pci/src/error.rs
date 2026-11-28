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
