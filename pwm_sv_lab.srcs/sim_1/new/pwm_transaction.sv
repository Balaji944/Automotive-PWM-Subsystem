`timescale 1ns / 1ps// ============================================================
// PWM Transaction Class
// Project  : Multi-Channel PWM CDV Environment
// Engineer : RVCE EC Dept
// Tool     : Vivado 2024.1 (xsim)
//
// This is the base data object passed between TB components.
// All stimulus is described as a transaction.
// ============================================================
// FIXED:
//   1. c_period_dist: max period reduced to 8000 to keep
//      simulation time bounded (matches generator fix).
//   2. c_deadband_valid: use period/4 as max instead of
//      period[8:1] which is a bit-select and evaluates wrong
//      for periods > 255.
//   3. post_randomize: ensure period is never 0 after snap.
// ============================================================
// ============================================================
// PWM Transaction - FINAL FIX
// period constraint tightened to match generator cap of 2000.
// ============================================================

`ifndef PWM_TRANSACTION_SV
`define PWM_TRANSACTION_SV

class pwm_transaction;

    rand logic [1:0]  channel_id;
    rand logic [15:0] duty;
    rand logic [15:0] period;
    rand logic [15:0] phase;
    rand logic        enable;
    rand logic        db_enable;
    rand logic [7:0]  deadband_cnt;
    rand logic [1:0]  resolution_mode;

    rand logic        inject_fault;
    rand logic [1:0]  fault_type;
    rand logic [7:0]  fault_addr;

    int               trans_id;
    realtime          timestamp;
    static int        trans_count = 0;

    constraint c_period {
        period inside {[50:2000]};
    }

    constraint c_duty_valid {
        duty <= period;
    }

    constraint c_phase_valid {
        phase < period;
    }

    constraint c_deadband_valid {
        deadband_cnt < (period / 4);
        deadband_cnt < 255;
    }

    constraint c_enable {
        enable dist {1 := 90, 0 := 10};
    }

    constraint c_db_enable {
        db_enable dist {1 := 70, 0 := 30};
    }

    constraint c_fault_rate {
        inject_fault dist {1 := 15, 0 := 85};
    }

    constraint c_duty_dist {
        duty dist {
            0                          := 5,
            [1       :(period/4)]      := 20,
            [(period/4):(period/2)]    := 25,
            [(period/2):(3*period/4)]  := 25,
            [(3*period/4):(period-1)]  := 20,
            period                     := 5
        };
    }

    constraint c_period_dist {
        period dist {
            [50:255]   := 30,
            [256:500]  := 30,
            [501:1000] := 25,
            [1001:2000]:= 15
        };
    }

    constraint c_channel {
        channel_id dist {0 := 25, 1 := 25, 2 := 25, 3 := 25};
    }

    function new();
        trans_count++;
        trans_id  = trans_count;
        timestamp = $realtime;
    endfunction

    function void post_randomize();
        if (duty < 2)           duty = 0;
        if (duty > period - 2)  duty = period;
        if (period == 0)        period = 50;

        if (deadband_cnt == 0 && db_enable)
            deadband_cnt = 4;
        if (deadband_cnt >= (period / 4))
            deadband_cnt = (period / 4) - 1;
        if (deadband_cnt == 0) deadband_cnt = 1;
    endfunction

    function void print(string prefix = "");
        $display(
          "%s[TRANS #%0d @ %0t] CH=%0d | duty=%0d | period=%0d | phase=%0d | en=%0b | db_en=%0b | db_cnt=%0d | fault=%0b(%0d)",
          prefix, trans_id, timestamp,
          channel_id, duty, period, phase,
          enable, db_enable, deadband_cnt,
          inject_fault, fault_type);
    endfunction

    function pwm_transaction clone();
        pwm_transaction t = new();
        t.channel_id   = this.channel_id;
        t.duty         = this.duty;
        t.period       = this.period;
        t.phase        = this.phase;
        t.enable       = this.enable;
        t.db_enable    = this.db_enable;
        t.deadband_cnt = this.deadband_cnt;
        t.inject_fault = this.inject_fault;
        t.fault_type   = this.fault_type;
        t.fault_addr   = this.fault_addr;
        return t;
    endfunction

    function real expected_duty_pct();
        if (period == 0) return 0.0;
        return (real'(duty) / real'(period)) * 100.0;
    endfunction

endclass

`endif