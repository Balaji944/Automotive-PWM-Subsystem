// ============================================================
// PWM Assertions (SVA)
// Project  : Multi-Channel PWM CDV Environment
// Engineer : RVCE EC Dept
// Tool     : Vivado 2024.1 (xsim)
//
// Bound to pwm_top via bind in tb_top.
// Properties verified every clock cycle throughout simulation.
//
// Assertions:
`timescale 1ns / 1ps//   A1 : No shoot-through (pwm_h & pwm_l never both HIGH)
//   A2 : Deadband enforced - pwm_l stays LOW after pwm_h falls
//   A3 : PWM output stable during reset
//   A4 : cycle_done pulses exactly 1 cycle wide
//   A5 : APB pready always asserted within 2 cycles of psel
//   A6 : fault_detected sticky - never clears without reset
//   A7 : pwm_raw and pwm_h relationship (h follows raw)
//   A8 : Counter never exceeds configured period
// ============================================================

module pwm_assertions (
    input logic        clk,
    input logic        rst_n,

    // APB
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [7:0]  paddr,
    input logic        pready,
    input logic        pslverr,

    // PWM outputs
    input logic [3:0]  pwm_h,
    input logic [3:0]  pwm_l,
    input logic [3:0]  pwm_raw,
    input logic [3:0]  db_active,
    input logic [3:0]  cycle_done,
    input logic        fault_detected,

    // Counters
    input logic [15:0] ch0_counter,
    input logic [15:0] ch1_counter,
    input logic [15:0] ch2_counter,
    input logic [15:0] ch3_counter
);

    // ============================================================
    // A1 : NO SHOOT-THROUGH on any channel
    // Both pwm_h and pwm_l must NEVER be HIGH simultaneously
    // ============================================================
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_shoot_assert
            property p_no_shoot_through;
                @(posedge clk) disable iff (!rst_n)
                !(pwm_h[i] && pwm_l[i]);
            endproperty

            A1_no_shoot_through: assert property (p_no_shoot_through)
                else $error("[ASSERT-FAIL] A1: Shoot-through on CH%0d @ %0t", i, $time);

            // Cover that we did exercise both outputs going high separately
            C1_pwm_h_seen: cover property (
                @(posedge clk) disable iff (!rst_n) pwm_h[i]);
            C1_pwm_l_seen: cover property (
                @(posedge clk) disable iff (!rst_n) pwm_l[i]);
        end
    endgenerate

    // ============================================================
    // A2 : DEADBAND ENFORCED
    // After pwm_h falls, pwm_l must stay LOW for at least 1 cycle
    // ============================================================
    generate
        for (i = 0; i < 4; i++) begin : gen_db_assert
            property p_deadband_hold;
                @(posedge clk) disable iff (!rst_n)
                // When pwm_h falls (1→0) AND deadband is active
                ($fell(pwm_h[i]) && db_active[i]) |=>
                !pwm_l[i];   // pwm_l must be LOW the very next cycle
            endproperty

            A2_deadband_hold: assert property (p_deadband_hold)
                else $error("[ASSERT-FAIL] A2: Deadband violation on CH%0d @ %0t", i, $time);
        end
    endgenerate

    // ============================================================
    // A3 : RESET CLEARS OUTPUTS
    // When rst_n is asserted (LOW), all PWM outputs must be LOW
    // ============================================================
    property p_reset_clears_outputs;
        @(posedge clk)
        !rst_n |-> (pwm_h == 4'b0 && pwm_l == 4'b0 && pwm_raw == 4'b0);
    endproperty

    A3_reset_clears: assert property (p_reset_clears_outputs)
        else $error("[ASSERT-FAIL] A3: Outputs not cleared during reset @ %0t", $time);

    // ============================================================
    // A4 : cycle_done IS A SINGLE-CYCLE PULSE
    // Must go LOW the cycle after it goes HIGH
    // ============================================================
    generate
        for (i = 0; i < 4; i++) begin : gen_done_assert
            property p_cycle_done_pulse;
                @(posedge clk) disable iff (!rst_n)
                $rose(cycle_done[i]) |=> !cycle_done[i];
            endproperty

            A4_cycle_done_pulse: assert property (p_cycle_done_pulse)
                else $error("[ASSERT-FAIL] A4: cycle_done[%0d] held HIGH >1 cycle @ %0t", i, $time);
        end
    endgenerate

    // ============================================================
    // A5 : APB PREADY WITHIN 2 CYCLES
    // Once psel is asserted, pready must come within 2 cycles
    // ============================================================
    property p_apb_pready;
        @(posedge clk) disable iff (!rst_n)
        (psel && !penable) |-> ##[1:2] pready;
    endproperty

    A5_apb_pready: assert property (p_apb_pready)
        else $error("[ASSERT-FAIL] A5: APB pready not seen within 2 cycles @ %0t", $time);

    // ============================================================
    // A6 : FAULT DETECTED IS STICKY
    // Once fault_detected goes HIGH, it stays HIGH until reset
    // ============================================================
    property p_fault_sticky;
        @(posedge clk) disable iff (!rst_n)
        $rose(fault_detected) |=> always fault_detected;
    endproperty

    A6_fault_sticky: assert property (p_fault_sticky)
        else $error("[ASSERT-FAIL] A6: fault_detected cleared without reset @ %0t", $time);

    // ============================================================
    // A7 : PWM_H FOLLOWS PWM_RAW (when no deadband)
    // When db_active is LOW, pwm_h must equal pwm_raw
    // ============================================================
    generate
        for (i = 0; i < 4; i++) begin : gen_raw_assert
            property p_pwm_h_follows_raw;
                @(posedge clk) disable iff (!rst_n)
                !db_active[i] |-> (pwm_h[i] == pwm_raw[i]);
            endproperty

            //A7_pwm_h_follows_raw: assert property (p_pwm_h_follows_raw)
                //else $error("[ASSERT-FAIL] A7: pwm_h[%0d] != pwm_raw[%0d] when no deadband @ %0t",
                  //           i, i, $time);
        end
    endgenerate

    // ============================================================
    // A8 : APB SLAVE ERROR ON INVALID ADDRESS
    // pslverr must be asserted when paddr = 0xFF
    // ============================================================
    property p_slverr_on_bad_addr;
        @(posedge clk) disable iff (!rst_n)
        (psel && penable && (paddr == 8'hFF)) |-> pslverr;
    endproperty

    A8_slverr_bad_addr: assert property (p_slverr_on_bad_addr)
        else $error("[ASSERT-FAIL] A8: pslverr not asserted on invalid addr 0xFF @ %0t", $time);

    // ============================================================
    // Cover properties - ensure interesting scenarios are exercised
    // ============================================================
    C_fault_detected:   cover property (@(posedge clk) $rose(fault_detected));
    C_db_active_ch0:    cover property (@(posedge clk) db_active[0]);
    C_all_ch_enabled:   cover property (@(posedge clk) disable iff(!rst_n)
                            (pwm_raw == 4'b1111));
    C_apb_slverr:       cover property (@(posedge clk) disable iff(!rst_n) pslverr);

    // ============================================================
    // Simulation summary on finish
    // ============================================================
    final begin
        $display("\n[ASSERT] Assertion check complete. Review above for any FAIL messages.");
    end

endmodule