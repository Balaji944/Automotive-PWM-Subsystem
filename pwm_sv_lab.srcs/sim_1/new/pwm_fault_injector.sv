`timescale 1ns / 1ps// ============================================================
// PWM Fault Injector
// ============================================================
`ifndef PWM_FAULT_INJECTOR_SV
`define PWM_FAULT_INJECTOR_SV

`include "pwm_transaction.sv"
`include "pwm_monitor.sv"

class pwm_fault_injector;

    virtual pwm_if vif;

    typedef struct {
        int       fault_id;
        int       channel_id;
        int       fault_type;
        realtime  inject_time;
        real      expected_duty_pct;
        real      actual_duty_pct;
        bit       detected;
        string    fault_name;
    } fault_log_t;

    fault_log_t fault_log[$];
    int         fault_id_counter = 0;

    string fault_names[4] = '{"STUCK_AT_0", "STUCK_AT_1", "BIT_FLIP", "WRONG_ADDR"};

    int total_faults    = 0;
    int detected_faults = 0;
    int missed_faults   = 0;
    int fault_type_count[4];

    function new(virtual pwm_if vi);
        vif = vi;
        foreach (fault_type_count[i]) fault_type_count[i] = 0;
    endfunction

    // --------------------------------------------------------
    // Log a fault injection event
    // --------------------------------------------------------
    function void log_fault(pwm_transaction trans);
        fault_log_t entry;

        fault_id_counter++;
        entry.fault_id    = fault_id_counter;
        entry.channel_id  = trans.channel_id;
        entry.fault_type  = trans.fault_type;
        entry.inject_time = $realtime;
        entry.fault_name  = fault_names[trans.fault_type];
        entry.detected    = 0;
        entry.actual_duty_pct = 0.0;

        case (trans.fault_type)
            0: entry.expected_duty_pct = 0.0;
            1: begin
                pwm_transaction temp_tx = new();
                temp_tx.period       = trans.period;
                temp_tx.db_enable    = trans.db_enable;
                temp_tx.deadband_cnt = trans.deadband_cnt;
                temp_tx.duty         = trans.period; // STUCK_AT_1 logic
                entry.expected_duty_pct = temp_tx.expected_duty_pct();
            end
            2: begin
                pwm_transaction temp_tx = new();
                automatic logic [15:0] flipped = trans.duty ^ 16'h00FF;
                temp_tx.period       = trans.period;
                temp_tx.db_enable    = trans.db_enable;
                temp_tx.deadband_cnt = trans.deadband_cnt;
                temp_tx.duty         = (flipped > trans.period) ? trans.period : flipped;
                entry.expected_duty_pct = temp_tx.expected_duty_pct();
            end
            3: begin
                entry.expected_duty_pct = trans.expected_duty_pct();
            end
        endcase

        fault_type_count[trans.fault_type]++;
        total_faults++;
        fault_log.push_back(entry);

        $display("[FAULT-INJ] #%0d CH%0d %s injected @ %0t | expected_duty=%.1f%%",
                  entry.fault_id, entry.channel_id, entry.fault_name,
                  entry.inject_time, entry.expected_duty_pct);
    endfunction

    // --------------------------------------------------------
    // Match Active Fault
    // --------------------------------------------------------
 function void check_fault(pwm_mon_result result);
        int  match_idx = -1;
        real duty_error;
        real tol;

        // Search from the END (most recent) for this channel
        for (int i = fault_log.size()-1; i >= 0; i--) begin
            if (fault_log[i].channel_id == result.channel_id &&
                !fault_log[i].detected) begin
                match_idx = i;
                break;
            end
        end

        if (match_idx < 0) return;

        // Always update actual duty to the latest seen
        fault_log[match_idx].actual_duty_pct = result.measured_duty_pct;

        if (fault_log[match_idx].fault_type == 0 ||
            fault_log[match_idx].fault_type == 1)
            tol = 5.0;
        else
            tol = 3.0;

        duty_error = fault_log[match_idx].expected_duty_pct -
                     result.measured_duty_pct;
        if (duty_error < 0) duty_error = -duty_error;

        // ONLY act on a successful match. Let it keep trying if it fails (it might be settling)
        if (duty_error < tol) begin
            fault_log[match_idx].detected = 1;
            detected_faults++;
            $display("[FAULT-DET] #%0d %s on CH%0d DETECTED | exp=%.1f%% meas=%.1f%%",
                      fault_log[match_idx].fault_id,
                      fault_log[match_idx].fault_name,
                      fault_log[match_idx].channel_id,
                      fault_log[match_idx].expected_duty_pct,
                      result.measured_duty_pct);
        end
    endfunction
    // --------------------------------------------------------
    // pslverr monitor
    // --------------------------------------------------------
    task monitor_slverr();
        forever begin
            @(posedge vif.clk);
            if (vif.pslverr && vif.psel && vif.penable) begin
                $display("[FAULT-INJ] pslverr detected on addr=0x%0h @ %0t",
                          vif.paddr, $realtime);
                for (int i = fault_log.size()-1; i >= 0; i--) begin
                    if (fault_log[i].fault_type == 3 &&
                        !fault_log[i].detected) begin
                        fault_log[i].detected = 1;
                        detected_faults++;
                        $display("[FAULT-DET] #%0d WRONG_ADDR on CH%0d via pslverr",
                                  fault_log[i].fault_id,
                                  fault_log[i].channel_id);
                        break;
                    end
                end
            end
        end
    endtask

    // --------------------------------------------------------
    // Final Report - Evaluates silent STUCK faults
    // --------------------------------------------------------
    function void report();
        // Sweep for STUCK faults that resulted in dead signal lines
        foreach (fault_log[i]) begin
            if (!fault_log[i].detected) begin
                int ch = fault_log[i].channel_id;
                
                // If it was STUCK_AT_0 and the line is actually flat low
                if (fault_log[i].fault_type == 0 && vif.pwm_h[ch] == 1'b0) begin
                    fault_log[i].detected = 1;
                    fault_log[i].actual_duty_pct = 0.0;
                    detected_faults++;
                end
                // If it was STUCK_AT_1 and the line is actually flat high
                else if (fault_log[i].fault_type == 1 && vif.pwm_h[ch] == 1'b1) begin
                    fault_log[i].detected = 1;
                    fault_log[i].actual_duty_pct = 100.0;
                    detected_faults++;
                end
            end
        end

        missed_faults = total_faults - detected_faults;

        $display("\n========================================");
        $display("      FAULT INJECTION REPORT");
        $display("========================================");
        $display("  Total faults injected : %0d", total_faults);
        $display("  Detected              : %0d", detected_faults);
        $display("  Missed                : %0d", missed_faults);
        if (total_faults > 0)
            $display("  Detection rate        : %.1f%%",
                      real'(detected_faults) / real'(total_faults) * 100.0);
        $display("----------------------------------------");
        $display("  By fault type:");
        $display("    STUCK_AT_0 : %0d injected", fault_type_count[0]);
        $display("    STUCK_AT_1 : %0d injected", fault_type_count[1]);
        $display("    BIT_FLIP   : %0d injected", fault_type_count[2]);
        $display("    WRONG_ADDR : %0d injected", fault_type_count[3]);
        $display("----------------------------------------");
        $display("  Fault log:");
        foreach (fault_log[i]) begin
            $display("    [%0d] CH%0d %-12s | exp=%.1f%% | act=%.1f%% | %s",
                      fault_log[i].fault_id,
                      fault_log[i].channel_id,
                      fault_log[i].fault_name,
                      fault_log[i].expected_duty_pct,
                      fault_log[i].actual_duty_pct,
                      fault_log[i].detected ? "DETECTED" : "MISSED");
        end
        $display("========================================\n");
    endfunction

endclass

`endif