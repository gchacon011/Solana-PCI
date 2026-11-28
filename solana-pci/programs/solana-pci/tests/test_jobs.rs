use anchor_lang::{
    prelude::{Clock, Pubkey},
    solana_program::{instruction::Instruction, system_program},
    AccountDeserialize, InstructionData, ToAccountMetas,
};
use litesvm::LiteSVM;
use solana_keypair::Keypair;
use solana_message::{Message, VersionedMessage};
use solana_signer::Signer;
use solana_transaction::versioned::VersionedTransaction;

const START_TIME: i64 = 1_800_000_000;
const LAMPORTS: u64 = 2_000_000_000;

fn setup_svm() -> (LiteSVM, Keypair, Keypair) {
    let program_id = solana_pci::id();
    let mut svm = LiteSVM::new();
    let program_bytes = include_bytes!(concat!(
        env!("CARGO_TARGET_TMPDIR"),
        "/../deploy/solana_pci.so"
    ));
    svm.add_program(program_id, program_bytes).unwrap();

    let authority = Keypair::new();
    let caller = Keypair::new();
    svm.airdrop(&authority.pubkey(), LAMPORTS).unwrap();
    svm.airdrop(&caller.pubkey(), LAMPORTS).unwrap();
    set_timestamp(&mut svm, START_TIME);

    (svm, authority, caller)
}

fn set_timestamp(svm: &mut LiteSVM, timestamp: i64) {
    let mut clock: Clock = svm.get_sysvar();
    clock.unix_timestamp = timestamp;
    svm.set_sysvar(&clock);
}

fn submit(svm: &mut LiteSVM, payer: &Keypair, instruction: Instruction) -> bool {
    // Force a fresh recent blockhash so repeated identical instructions are
    // distinct transactions; duplicate checks reach the program logic.
    svm.expire_blockhash();
    let blockhash = svm.latest_blockhash();
    let message = Message::new_with_blockhash(&[instruction], Some(&payer.pubkey()), &blockhash);
    let transaction =
        VersionedTransaction::try_new(VersionedMessage::Legacy(message), &[payer]).unwrap();
    svm.send_transaction(transaction).is_ok()
}

fn job_address(authority: &Pubkey, job_id: u64) -> Pubkey {
    let job_id_bytes = job_id.to_le_bytes();
    Pubkey::find_program_address(
        &[
            solana_pci::constants::JOB_SEED,
            authority.as_ref(),
            &job_id_bytes,
        ],
        &solana_pci::id(),
    )
    .0
}

fn create_job_instruction(
    authority: &Keypair,
    job_id: u64,
    interval_seconds: u64,
    first_run_at: i64,
) -> (Pubkey, Instruction) {
    let authority_key = authority.pubkey();
    let job = job_address(&authority_key, job_id);
    let instruction = Instruction::new_with_bytes(
        solana_pci::id(),
        &solana_pci::instruction::CreateJob {
            job_id,
            interval_seconds,
            first_run_at,
        }
        .data(),
        solana_pci::accounts::CreateJob {
            authority: authority_key,
            job,
            system_program: system_program::ID,
        }
        .to_account_metas(None),
    );
    (job, instruction)
}

fn execute_job_instruction(caller: &Keypair, job: Pubkey) -> Instruction {
    Instruction::new_with_bytes(
        solana_pci::id(),
        &solana_pci::instruction::ExecuteJob {}.data(),
        solana_pci::accounts::ExecuteJob {
            job,
            caller: caller.pubkey(),
        }
        .to_account_metas(None),
    )
}

fn pause_job_instruction(authority: &Keypair, job: Pubkey, paused: bool) -> Instruction {
    Instruction::new_with_bytes(
        solana_pci::id(),
        &solana_pci::instruction::SetJobPaused { paused }.data(),
        solana_pci::accounts::SetJobPaused {
            authority: authority.pubkey(),
            job,
        }
        .to_account_metas(None),
    )
}

fn load_job(svm: &LiteSVM, address: &Pubkey) -> solana_pci::state::Job {
    let account = svm.get_account(address).expect("job account must exist");
    let mut data: &[u8] = &account.data;
    solana_pci::state::Job::try_deserialize(&mut data).unwrap()
}

#[test]
fn test_create_job_validates_interval_and_start_time() {
    let (mut svm, authority, _) = setup_svm();

    let (job, valid_ix) = create_job_instruction(&authority, 1, 60, START_TIME + 60);
    assert!(submit(&mut svm, &authority, valid_ix));
    let state = load_job(&svm, &job);
    assert_eq!(state.authority, authority.pubkey());
    assert_eq!(state.job_id, 1);
    assert_eq!(state.interval_seconds, 60);
    assert_eq!(state.next_run_at, START_TIME + 60);
    assert_eq!(state.execution_count, 0);
    assert!(!state.paused);

    let (_, zero_interval_ix) = create_job_instruction(&authority, 2, 0, START_TIME + 60);
    assert!(!submit(&mut svm, &authority, zero_interval_ix));

    let (_, past_start_ix) = create_job_instruction(&authority, 3, 60, START_TIME - 1);
    assert!(!submit(&mut svm, &authority, past_start_ix));
}

#[test]
fn test_execute_job_requires_due_time_and_blocks_duplicate_period() {
    let (mut svm, authority, caller) = setup_svm();
    let first_run_at = START_TIME + 30;
    let interval = 60;
    let (job, create_ix) = create_job_instruction(&authority, 10, interval, first_run_at);
    assert!(submit(&mut svm, &authority, create_ix));

    let early_ix = execute_job_instruction(&caller, job);
    assert!(!submit(&mut svm, &caller, early_ix));

    set_timestamp(&mut svm, first_run_at);
    let due_ix = execute_job_instruction(&caller, job);
    assert!(submit(&mut svm, &caller, due_ix));

    let state = load_job(&svm, &job);
    assert_eq!(state.execution_count, 1);
    assert_eq!(state.last_run_at, first_run_at);
    assert_eq!(state.next_run_at, first_run_at + interval as i64);

    let duplicate_ix = execute_job_instruction(&caller, job);
    assert!(!submit(&mut svm, &caller, duplicate_ix));
    assert_eq!(load_job(&svm, &job).execution_count, 1);
}

#[test]
fn test_pause_resume_is_authority_controlled() {
    let (mut svm, authority, caller) = setup_svm();
    let first_run_at = START_TIME + 10;
    let (job, create_ix) = create_job_instruction(&authority, 20, 30, first_run_at);
    assert!(submit(&mut svm, &authority, create_ix));

    let pause_ix = pause_job_instruction(&authority, job, true);
    assert!(submit(&mut svm, &authority, pause_ix));
    assert!(load_job(&svm, &job).paused);

    set_timestamp(&mut svm, first_run_at);
    let while_paused_ix = execute_job_instruction(&caller, job);
    assert!(!submit(&mut svm, &caller, while_paused_ix));
    assert_eq!(load_job(&svm, &job).execution_count, 0);

    let unauthorized_resume_ix = pause_job_instruction(&caller, job, false);
    assert!(!submit(&mut svm, &caller, unauthorized_resume_ix));
    assert!(load_job(&svm, &job).paused);

    let resume_ix = pause_job_instruction(&authority, job, false);
    assert!(submit(&mut svm, &authority, resume_ix));
    assert!(!load_job(&svm, &job).paused);

    let execute_ix = execute_job_instruction(&caller, job);
    assert!(submit(&mut svm, &caller, execute_ix));
    assert_eq!(load_job(&svm, &job).execution_count, 1);
}
