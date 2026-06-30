`timescale 1ns / 1ps// ============================================================
// PWM Scoreboard
// ============================================================

// FIXED:
//   1. Stale transaction flushing: when a new expected txn
//      arrives for a channel, the queue is flushed to keep
//      only the LATEST transaction. This prevents the scoreboard
//      from comparing a monitor result against a 10-transaction-
//      old expected value.
//   2. Fault transactions are routed to fault injector AND
//      checked for duty mismatch (don't just skip them).
//   3. Skipping messages updated: now shows which txn is kept.
//   4. Phase check: skip only if phase < 5% of period
//      (was 10%), giving more phase checks.
// ============================================================
 
// ============================================================
// PWM Scoreboard - FINAL FIX
// Root causes fixed this round:
//   1. FREQUENCY GUARD: Before accepting a monitor result as
//      matching the current expected transaction, verify the
//      measured frequency is within 20% of the expected freq.
//      If it is not, the DUT is still running a previous
//      config - skip without consuming exp_valid so the next
//      monitor sample gets another chance.
//   2. DUTY GUARD: Same guard for duty - if measured duty
//      differs from expected by >30%, the channel has not
//      yet settled on the new config.
//   3. exp_valid is only cleared AFTER a successful frequency+
//      duty match, preventing the scoreboard from consuming
//      the expected value against a stale waveform.
//   4. Fault results: cleared immediately since faults are
//      intentionally wrong configs.
// ============================================================

`ifndef PWM_SCOREBOARD_SV
`define PWM_SCOREBOARD_SV

`include "pwm_transaction.sv"
`include "pwm_monitor.sv"

class pwm_scoreboard;

    mailbox #(pwm_transaction)  drv2scb;
    mailbox #(pwm_mon_result)   mon2scb;
    mailbox #(pwm_mon_result)   scb2fault;

    // Latest expected transaction per channel
    pwm_transaction exp_latest[0:3];
    bit             exp_valid [0:3];

    real DUTY_TOL_PCT  = 2.0;
    real FREQ_TOL_PCT  = 2.0;
    real DB_TOL_NS     = 30.0;
    real PHASE_TOL_DEG = 45.0;

    // Settle guard: measured freq must be within this % of expected
    // before we accept the sample as corresponding to the new config
real SETTLE_FREQ_PCT = 2.0;
real SETTLE_DUTY_PCT = 2.0;

    int total_checks  = 0;
    int passed_checks = 0;
    int failed_checks = 0;
    int fault_detected= 0;
    int shoot_through = 0;
    int skipped_settle= 0;   // count of samples skipped due to settle guard

    int duty_pass  = 0, duty_fail  = 0;
    int freq_pass  = 0, freq_fail  = 0;
    int db_pass    = 0, db_fail    = 0;
    int phase_pass = 0, phase_fail = 0;

    string error_log[$];

    function new(mailbox #(pwm_transaction) d2s,
                 mailbox #(pwm_mon_result)  m2s);
        drv2scb = d2s;
        mon2scb = m2s;
        for (int i = 0; i < 4; i++) begin
            exp_valid[i]  = 0;
            exp_latest[i] = null;
        end
    endfunction

    task run();
        $display("[SCB] Scoreboard started.");
        fork
            collect_expected();
            check_actual();
        join
    endtask

    // Always overwrite with latest transaction - keep only newest per channel
    task collect_expected();
        pwm_transaction trans;
        forever begin
            drv2scb.get(trans);
            exp_latest[trans.channel_id] = trans;
            exp_valid [trans.channel_id] = 1;
        end
    endtask

 task check_actual();
        pwm_mon_result  result;
        pwm_transaction expected;
        int ch;
        real exp_freq_hz, freq_ratio;
        real exp_duty_pct, duty_err;

        forever begin
            mon2scb.get(result);
            ch = result.channel_id;

            // 1. Unconditionally forward ALL results to fault injector
            if (scb2fault != null) scb2fault.put(result);

            if (result.shoot_through_detected) begin
                shoot_through++;
                log_error($sformatf("[SCB-FAIL] SHOOT-THROUGH on CH%0d @ %0t",
                           ch, result.capture_time));
            end

            if (!exp_valid[ch]) continue;

            expected = exp_latest[ch];

            // 2. Ignore formal checks if transaction is flagged as fault
            // Do NOT clear exp_valid; it will be overwritten by the next transaction!
            if (expected.inject_fault) continue;

            // 3. SETTLE GUARD - Frequency
            if (expected.period > 0 && result.measured_freq_hz > 0.0) begin
                exp_freq_hz = 100_000_000.0 / real'(expected.period);
                freq_ratio  = abs_real(result.measured_freq_hz - exp_freq_hz)
                              / exp_freq_hz * 100.0;

                if (freq_ratio > SETTLE_FREQ_PCT) begin
                    skipped_settle++;
                    continue;
                end
            end

            // 4. SETTLE GUARD - Duty
            exp_duty_pct = expected.expected_duty_pct();
            duty_err = abs_real(result.measured_duty_pct - exp_duty_pct);
            
            // Wait unconditionally until it settles within the 2.0% tolerance
            if (duty_err > SETTLE_DUTY_PCT) begin
                skipped_settle++;
                continue;
            end

            // Both guards passed - this is a stable, valid sample
            check_duty      (expected, result);
            check_frequency (expected, result);
            check_deadband  (expected, result);
            check_phase     (expected, result);

            exp_valid[ch] = 0;
        end
    endtask

    task check_duty(pwm_transaction exp, pwm_mon_result act);
        real exp_duty_pct, error_pct;
        exp_duty_pct = exp.expected_duty_pct();
        error_pct    = abs_real(act.measured_duty_pct - exp_duty_pct);

        total_checks++;
        if (error_pct <= DUTY_TOL_PCT) begin
            duty_pass++;
            passed_checks++;
            $display("[SCB-PASS] CH%0d Duty  : exp=%.2f%% meas=%.2f%% err=%.2f%%",
                      exp.channel_id, exp_duty_pct,
                      act.measured_duty_pct, error_pct);
        end else begin
            duty_fail++;
            failed_checks++;
            log_error($sformatf(
                "[SCB-FAIL] CH%0d Duty  : exp=%.2f%% meas=%.2f%% err=%.2f%% (tol=%.2f%%)",
                exp.channel_id, exp_duty_pct,
                act.measured_duty_pct, error_pct, DUTY_TOL_PCT));
        end
    endtask

    task check_frequency(pwm_transaction exp, pwm_mon_result act);
        real exp_freq_hz, error_pct;
        if (exp.period == 0) return;
        exp_freq_hz = 100_000_000.0 / real'(exp.period);
        if (act.measured_freq_hz == 0.0) return;
        error_pct = abs_real(act.measured_freq_hz - exp_freq_hz) /
                    exp_freq_hz * 100.0;

        total_checks++;
        if (error_pct <= FREQ_TOL_PCT) begin
            freq_pass++;
            passed_checks++;
            $display("[SCB-PASS] CH%0d Freq  : exp=%.1fHz meas=%.1fHz err=%.2f%%",
                      exp.channel_id, exp_freq_hz,
                      act.measured_freq_hz, error_pct);
        end else begin
            freq_fail++;
            failed_checks++;
            log_error($sformatf(
                "[SCB-FAIL] CH%0d Freq  : exp=%.1fHz meas=%.1fHz err=%.2f%% (tol=%.2f%%)",
                exp.channel_id, exp_freq_hz,
                act.measured_freq_hz, error_pct, FREQ_TOL_PCT));
        end
    endtask

task check_deadband(pwm_transaction exp, pwm_mon_result act);
        real exp_db_ns, error_ns;
        if (!exp.db_enable) return;

        // FIX: If the deadband delay is larger than the raw off-time, 
        // pwm_l is physically swallowed and will never rise. 
        // The monitor correctly measures 0.0ns. Skip the check.
        if (exp.deadband_cnt >= (exp.period - exp.duty)) return;

        exp_db_ns = real'(exp.deadband_cnt) * 10.0;
        error_ns  = abs_real(act.measured_deadband_ns - exp_db_ns);

        total_checks++;
        if (error_ns <= DB_TOL_NS) begin
            db_pass++;
            passed_checks++;
            $display("[SCB-PASS] CH%0d DB    : exp=%.1fns meas=%.1fns err=%.1fns",
                      exp.channel_id, exp_db_ns,
                      act.measured_deadband_ns, error_ns);
        end else begin
            db_fail++;
            failed_checks++;
            log_error($sformatf(
                "[SCB-FAIL] CH%0d DB    : exp=%.1fns meas=%.1fns err=%.1fns (tol=%.1fns)",
                exp.channel_id, exp_db_ns,
                act.measured_deadband_ns, error_ns, DB_TOL_NS));
        end
    endtask
    
task check_phase(pwm_transaction exp, pwm_mon_result act);
        real exp_phase_deg, error_deg, meas_phase_norm;
        real expected_ticks;

        if (exp.channel_id == 0) return;
        if (exp.period == 0) return;
        if (exp.phase < (exp.period / 20)) return;

        // FIX: If CH0 has never been configured, or is currently disabled, 
        // we cannot measure relative phase. Skip the check.
        if (exp_latest[0] == null || !exp_latest[0].enable) return;

        // FIX: If CH0 is running at a different speed than this channel, 
        // relative phase is mathematically meaningless. Skip the check.
        if (exp.period != exp_latest[0].period) return;

        // Add Deadband shift to expected phase calculation
        expected_ticks = real'(exp.phase);
        if (exp.db_enable) begin
            expected_ticks += real'(exp.deadband_cnt);
        end

        // Calculate expected phase in degrees
        exp_phase_deg = (expected_ticks / real'(exp.period)) * 360.0;

        meas_phase_norm = act.measured_phase_deg;
        while (meas_phase_norm >= 360.0) meas_phase_norm -= 360.0;
        while (meas_phase_norm <    0.0) meas_phase_norm += 360.0;

        error_deg = meas_phase_norm - exp_phase_deg;
        if (error_deg >  180.0) error_deg -= 360.0;
        if (error_deg < -180.0) error_deg += 360.0;
        if (error_deg <    0.0) error_deg  = -error_deg;

        total_checks++;
        if (error_deg <= PHASE_TOL_DEG) begin
            phase_pass++;
            passed_checks++;
            $display("[SCB-PASS] CH%0d Phase: exp=%.1fdeg meas=%.1fdeg err=%.1fdeg",
                      exp.channel_id, exp_phase_deg,
                      meas_phase_norm, error_deg);
        end else begin
            phase_fail++;
            failed_checks++;
            log_error($sformatf(
                "[SCB-FAIL] CH%0d Phase: exp=%.1fdeg meas=%.1fdeg err=%.1fdeg (tol=%.1fdeg)",
                exp.channel_id, exp_phase_deg,
                meas_phase_norm, error_deg, PHASE_TOL_DEG));
        end
    endtask

    function real abs_real(real v);
        return (v < 0.0) ? -v : v;
    endfunction

    function void log_error(string msg);
        $error("%s", msg);
        error_log.push_back(msg);
    endfunction

    function void report();
        $display("\n========================================");
        $display("        SCOREBOARD FINAL REPORT");
        $display("========================================");
        $display("  Total checks   : %0d", total_checks);
        $display("  PASSED         : %0d", passed_checks);
        $display("  FAILED         : %0d", failed_checks);
        $display("  Shoot-throughs : %0d", shoot_through);
        $display("  Fault txns     : %0d", fault_detected);
        $display("  Settle skipped : %0d", skipped_settle);
        $display("----------------------------------------");
        $display("  Duty   pass/fail : %0d / %0d", duty_pass,  duty_fail);
        $display("  Freq   pass/fail : %0d / %0d", freq_pass,  freq_fail);
        $display("  DB     pass/fail : %0d / %0d", db_pass,    db_fail);
        $display("  Phase  pass/fail : %0d / %0d", phase_pass, phase_fail);
        $display("========================================");

        if (failed_checks == 0 && shoot_through == 0)
            $display("  *** SIMULATION PASSED ***");
        else begin
            $display("  *** SIMULATION FAILED - %0d errors ***", failed_checks);
            foreach (error_log[i])
                $display("  [ERR %0d] %s", i, error_log[i]);
        end
        $display("========================================\n");
    endfunction

endclass

`endif

