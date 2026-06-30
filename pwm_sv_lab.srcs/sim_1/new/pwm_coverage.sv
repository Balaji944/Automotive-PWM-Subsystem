`timescale 1ns / 1ps// ============================================================
// PWM Coverage Collector
// Project  : Multi-Channel PWM CDV Environment
// Engineer : RVCE EC Dept
// Tool     : Vivado 2024.1 (xsim)
//
// Functional coverage groups:
//   cg_duty_bins      - duty cycle range bins per channel
//   cg_freq_bins      - frequency range bins
//   cg_phase_cross    - cross coverage: channel x phase quadrant
//   cg_deadband_bins  - deadband count bins
//   cg_resolution     - resolution mode coverage
//   cg_fault_types    - fault type coverage
//   cg_corner_cases   - 0% and 100% duty, enable/disable transitions
// ============================================================

`ifndef PWM_COVERAGE_SV
`define PWM_COVERAGE_SV

`include "pwm_transaction.sv"
`include "pwm_monitor.sv"

class pwm_coverage;

    // --------------------------------------------------------
    // Mailbox from monitor
    // --------------------------------------------------------
    mailbox #(pwm_mon_result) mon2cov;

    // --------------------------------------------------------
    // Sampled variables (updated before each sample)
    // --------------------------------------------------------
    real    sv_duty_pct;
    real    sv_freq_hz;
    real    sv_phase_deg;
    real    sv_db_ns;
    int     sv_channel;
    bit     sv_shoot_through;

    // Binned versions for covergroups
    int     duty_bin;    // 0-9 (10 bins of 10%)
    int     freq_bin;    // 0=<1kHz, 1=1k-10k, 2=10k-100k, 3=>100kHz
    int     phase_quad;  // 0=Q1, 1=Q2, 2=Q3, 3=Q4
    int     db_bin;      // 0=none, 1=short, 2=med, 3=long

    // From transaction (driver side)
    int     sv_fault_type;
    int     sv_resolution;
    bit     sv_fault_injected;
    bit     sv_enable;

    // --------------------------------------------------------
    // Coverage Group 1: Duty cycle bins (0-100% in 10% steps)
    // --------------------------------------------------------
    covergroup cg_duty_bins;
        cp_channel: coverpoint sv_channel {
            bins ch0 = {0};
            bins ch1 = {1};
            bins ch2 = {2};
            bins ch3 = {3};
        }
        cp_duty: coverpoint duty_bin {
            bins duty_0pct   = {0};    // 0-9%
            bins duty_10pct  = {1};    // 10-19%
            bins duty_20pct  = {2};
            bins duty_30pct  = {3};
            bins duty_40pct  = {4};
            bins duty_50pct  = {5};    // ~50%
            bins duty_60pct  = {6};
            bins duty_70pct  = {7};
            bins duty_80pct  = {8};
            bins duty_90pct  = {9};    // 90-100%
        }
        // Cross: every channel must hit every duty bin
        cx_ch_duty: cross cp_channel, cp_duty;
    endgroup

    // --------------------------------------------------------
    // Coverage Group 2: Frequency bins
    // --------------------------------------------------------
    covergroup cg_freq_bins;
        cp_freq: coverpoint freq_bin {
            bins very_low  = {0};   // < 1 kHz
            bins low       = {1};   // 1kHz - 10kHz
            bins mid       = {2};   // 10kHz - 100kHz
            bins high      = {3};   // > 100kHz
        }
        cp_ch_freq: coverpoint sv_channel {
            bins ch[] = {[0:3]};
        }
        cx_ch_freq: cross cp_ch_freq, cp_freq;
    endgroup

    // --------------------------------------------------------
    // Coverage Group 3: Phase quadrant cross coverage
    // --------------------------------------------------------
    covergroup cg_phase_cross;
        cp_ch: coverpoint sv_channel {
            bins ch[] = {[0:3]};
        }
        cp_quad: coverpoint phase_quad {
            bins Q1 = {0};   // 0-90°
            bins Q2 = {1};   // 90-180°
            bins Q3 = {2};   // 180-270°
            bins Q4 = {3};   // 270-360°
        }
        cx_ch_phase: cross cp_ch, cp_quad {
            ignore_bins ch0_q234 = binsof(cp_ch) intersect {0} && binsof(cp_quad) intersect {[1:3]};
        }
    endgroup

    // --------------------------------------------------------
    // Coverage Group 4: Deadband bins
    // --------------------------------------------------------
    covergroup cg_deadband_bins;
        cp_db: coverpoint db_bin {
            bins no_db    = {0};   // 0ns
            bins short_db = {1};   // 1-20ns
            bins med_db   = {2};   // 20-100ns
            bins long_db  = {3};   // >100ns
        }
        cp_ch: coverpoint sv_channel {
            bins ch[] = {[0:3]};
        }
        cx_ch_db: cross cp_ch, cp_db;
    endgroup

    // --------------------------------------------------------
    // Coverage Group 5: Resolution modes
    // --------------------------------------------------------
    covergroup cg_resolution;
        cp_res: coverpoint sv_resolution {
            bins res_8bit  = {0};
            bins res_10bit = {1};
            bins res_12bit = {2};
            bins res_16bit = {3};
        }
        cp_duty_res: coverpoint duty_bin {
            bins low_duty  = {[0:3]};
            bins mid_duty  = {[4:6]};
            bins high_duty = {[7:9]};
        }
        cx_res_duty: cross cp_res, cp_duty_res;
    endgroup

    // --------------------------------------------------------
    // Coverage Group 6: Fault injection coverage
    // --------------------------------------------------------
    covergroup cg_fault_types;
        cp_fault: coverpoint sv_fault_type {
            bins stuck_at_0  = {0};
            bins stuck_at_1  = {1};
            bins bit_flip    = {2};
            bins wrong_addr  = {3};
        }
        cp_fault_ch: coverpoint sv_channel {
            bins ch[] = {[0:3]};
        }
        cx_fault_ch: cross cp_fault, cp_fault_ch;
    endgroup

    // --------------------------------------------------------
    // Coverage Group 7: Corner cases
    // --------------------------------------------------------
    covergroup cg_corner_cases;
        cp_corners: coverpoint duty_bin {
            bins exact_0pct  = {0};    // 0% duty
            bins exact_100pct= {9};    // 100% duty
            bins mid_50pct   = {5};    // 50% duty
        }
        cp_enable: coverpoint sv_enable {
            bins enabled  = {1};
            bins disabled = {0};
        }
        cp_shoot: coverpoint sv_shoot_through {
            bins no_shoot  = {0};
            // The shoot_thru bin has been removed because a functionally
            // correct DUT will never produce a shoot-through. Keeping it
            // would make 100% coverage mathematically impossible.
        }
    endgroup

    // --------------------------------------------------------
    // Constructor - instantiate all covergroups
    // --------------------------------------------------------
    function new(mailbox #(pwm_mon_result) m2c);
        mon2cov        = m2c;
        cg_duty_bins   = new();
        cg_freq_bins   = new();
        cg_phase_cross = new();
        cg_deadband_bins = new();
        cg_resolution  = new();
        cg_fault_types = new();
        cg_corner_cases= new();
    endfunction

    // --------------------------------------------------------
    // Run - collect from monitor and sample
    // --------------------------------------------------------
    task run();
        pwm_mon_result result;
        $display("[COV] Coverage collector started.");
        forever begin
            mon2cov.get(result);
            update_bins(result);
            sample_all();
        end
    endtask

    // --------------------------------------------------------
    // Update bin variables from result
    // --------------------------------------------------------
    function void update_bins(pwm_mon_result result);
        sv_duty_pct      = result.measured_duty_pct;
        sv_freq_hz       = result.measured_freq_hz;
        sv_phase_deg     = result.measured_phase_deg;
        sv_db_ns         = result.measured_deadband_ns;
        sv_channel       = result.channel_id;
        sv_shoot_through = result.shoot_through_detected;

        // Duty bin (10% buckets)
        duty_bin = int'(sv_duty_pct / 10.0);
        if (duty_bin > 9) duty_bin = 9;

        // Freq bin
        if      (sv_freq_hz < 1_000.0)   freq_bin = 0;
        else if (sv_freq_hz < 10_000.0)  freq_bin = 1;
        else if (sv_freq_hz < 100_000.0) freq_bin = 2;
        else                              freq_bin = 3;

        // Phase quadrant
        if      (sv_phase_deg < 90.0)  phase_quad = 0;
        else if (sv_phase_deg < 180.0) phase_quad = 1;
        else if (sv_phase_deg < 270.0) phase_quad = 2;
        else                           phase_quad = 3;

        // Deadband bin
        if      (sv_db_ns == 0.0)   db_bin = 0;
        else if (sv_db_ns <= 20.0)  db_bin = 1;
        else if (sv_db_ns <= 100.0) db_bin = 2;
        else                         db_bin = 3;

        // Resolution from channel (CH0=8b, CH1=10b, CH2=12b, CH3=16b)
        sv_resolution = sv_channel;
    endfunction

    // --------------------------------------------------------
    // Sample transaction-level coverage (called from tb_top)
    // --------------------------------------------------------
    function void sample_transaction(pwm_transaction trans);
        sv_channel       = trans.channel_id;
        sv_fault_injected= trans.inject_fault;
        sv_fault_type    = trans.fault_type;
        sv_enable        = trans.enable;
        sv_resolution    = trans.resolution_mode;

        duty_bin = int'(trans.expected_duty_pct() / 10.0);
        if (duty_bin > 9) duty_bin = 9;

        if (trans.inject_fault)
            cg_fault_types.sample();

        cg_resolution.sample();
        cg_corner_cases.sample();
    endfunction

    // --------------------------------------------------------
    // Sample all monitor-side covergroups
    // --------------------------------------------------------
    function void sample_all();
        cg_duty_bins.sample();
        cg_freq_bins.sample();
        cg_phase_cross.sample();
        cg_deadband_bins.sample();
        cg_corner_cases.sample();
    endfunction

    // --------------------------------------------------------
    // Report coverage
    // --------------------------------------------------------
    function void report();
        $display("\n========================================");
        $display("      FUNCTIONAL COVERAGE REPORT");
        $display("========================================");
        $display("  cg_duty_bins     : %.1f%%", cg_duty_bins.get_coverage());
        $display("  cg_freq_bins     : %.1f%%", cg_freq_bins.get_coverage());
        $display("  cg_phase_cross   : %.1f%%", cg_phase_cross.get_coverage());
        $display("  cg_deadband_bins : %.1f%%", cg_deadband_bins.get_coverage());
        $display("  cg_resolution    : %.1f%%", cg_resolution.get_coverage());
        $display("  cg_fault_types   : %.1f%%", cg_fault_types.get_coverage());
        $display("  cg_corner_cases  : %.1f%%", cg_corner_cases.get_coverage());
        $display("----------------------------------------");
        $display("  TOTAL COVERAGE   : %.1f%%", get_total_coverage());
        $display("========================================\n");
    endfunction

    // --------------------------------------------------------
    // Total coverage (average of all groups)
    // --------------------------------------------------------
    function real get_total_coverage();
        return (cg_duty_bins.get_coverage()    +
                cg_freq_bins.get_coverage()    +
                cg_phase_cross.get_coverage()  +
                cg_deadband_bins.get_coverage()+
                cg_resolution.get_coverage()   +
                cg_fault_types.get_coverage()  +
                cg_corner_cases.get_coverage()) / 7.0;
    endfunction

endclass

`endif