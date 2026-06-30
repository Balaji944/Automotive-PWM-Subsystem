`timescale 1ns / 1ps// ============================================================
// PWM Interface
// Project  : Multi-Channel PWM CDV Environment
// ============================================================

`ifndef PWM_IF_SV
`define PWM_IF_SV

interface pwm_if (
    input logic clk,
    input logic rst_n
);
    // APB signals
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [7:0]  paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // PWM outputs
    logic [3:0]  pwm_h;
    logic [3:0]  pwm_l;
    logic [3:0]  pwm_raw;
    logic [3:0]  db_active;
    logic [3:0]  cycle_done;
    logic        fault_detected;

    // Counter outputs
    logic [15:0] ch0_counter;
    logic [15:0] ch1_counter;
    logic [15:0] ch2_counter;
    logic [15:0] ch3_counter;

    // Clocking block for driver
    clocking drv_cb @(posedge clk);
        output psel, penable, pwrite, paddr, pwdata;
        input  pready, pslverr;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge clk);
        input pwm_h, pwm_l, pwm_raw, db_active, cycle_done;
        input fault_detected;
        input ch0_counter, ch1_counter, ch2_counter, ch3_counter;
        input psel, penable, pwrite, paddr, pwdata;
        input pready, pslverr;
    endclocking

    // Modports
    modport DUT (
        input clk, rst_n,
        input psel, penable, pwrite, paddr, pwdata,
        output prdata, pready, pslverr,
        output pwm_h, pwm_l, pwm_raw,
        output db_active, cycle_done, fault_detected,
        output ch0_counter, ch1_counter, ch2_counter, ch3_counter
    );

    modport TB (
        input clk, rst_n,
        output psel, penable, pwrite, paddr, pwdata,
        input prdata, pready, pslverr,
        input pwm_h, pwm_l, pwm_raw,
        input db_active, cycle_done, fault_detected,
        input ch0_counter, ch1_counter, ch2_counter, ch3_counter
    );

endinterface

`endif