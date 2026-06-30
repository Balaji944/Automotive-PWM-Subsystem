`timescale 1ns / 1ps// ============================================================
// PWM Channel - Single Parameterized PWM Channel
// Project  : Multi-Channel PWM CDV Environment
// Engineer : RVCE EC Dept
// Tool     : Vivado 2024.1 (xsim)
// ============================================================
// FIXED:
//   1. Phase counter and main counter both reset when cfg_valid
//      fires, so every new transaction starts a fresh period.
//      Previously the phase counter kept running across
//      transactions causing phase_done to stay permanently set,
//      which meant the phase offset was never applied again.
//   2. period_reg default changed to 1000 (matches pwm_top)
//      so the channel does not run at maximum speed on reset.
// ============================================================
 
module pwm_channel #(
    parameter RESOLUTION = 8,
    parameter CLK_FREQ   = 100_000_000
)(
    input  logic        clk,
    input  logic        rst_n,
 
    input  logic        cfg_valid,
    input  logic [15:0] cfg_duty,
    input  logic [15:0] cfg_period,
    input  logic [15:0] cfg_phase,
    input  logic        cfg_enable,
 
    output logic        pwm_out,
    output logic        pwm_out_n,
    output logic [15:0] counter_out,
    output logic        cycle_done
);
 
    logic [15:0] duty_reg;
    logic [15:0] period_reg;
    logic [15:0] phase_reg;
    logic        enable_reg;
 
    logic [15:0] counter;
    logic [15:0] phase_counter;
    logic        phase_done;
    logic        pwm_raw;
 
    // --------------------------------------------------------
    // Config latch - latch on cfg_valid pulse
    // FIX: also reset counters here so new transaction starts fresh
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            duty_reg   <= '0;
            period_reg <= 16'd1000;
            phase_reg  <= '0;
            enable_reg <= 1'b0;
        end else if (cfg_valid) begin
            duty_reg   <= cfg_duty;
            period_reg <= (cfg_period == 0) ? 16'd1 : cfg_period;
            phase_reg  <= cfg_phase;
            enable_reg <= cfg_enable;
        end
    end
 
    // --------------------------------------------------------
    // FIX: Phase counter resets on every cfg_valid so each new
    // transaction properly applies its phase offset from t=0.
    // Previously phase_done stayed HIGH across transactions
    // because it was only cleared on !enable_reg.
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_counter <= '0;
            phase_done    <= 1'b0;
        end else if (cfg_valid) begin
            // Reset phase tracking for every new transaction
            phase_counter <= '0;
            phase_done    <= (cfg_phase == 0) ? 1'b1 : 1'b0;
        end else if (!enable_reg) begin
            phase_counter <= '0;
            phase_done    <= 1'b0;
        end else if (!phase_done) begin
            if (phase_counter >= phase_reg - 1) begin
                phase_done <= 1'b1;
            end else begin
                phase_counter <= phase_counter + 1'b1;
            end
        end
    end
 
    // --------------------------------------------------------
    // Main PWM counter - also resets on cfg_valid
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= '0;
            cycle_done <= 1'b0;
        end else if (cfg_valid) begin
            counter    <= '0;
            cycle_done <= 1'b0;
        end else if (!enable_reg || !phase_done) begin
            counter    <= '0;
            cycle_done <= 1'b0;
        end else begin
            if (counter >= period_reg - 1) begin
                counter    <= '0;
                cycle_done <= 1'b1;
            end else begin
                counter    <= counter + 1'b1;
                cycle_done <= 1'b0;
            end
        end
    end
 
    // --------------------------------------------------------
    // PWM compare logic
    // --------------------------------------------------------
    always_comb begin
        if (!enable_reg || !phase_done)
            pwm_raw = 1'b0;
        else if (duty_reg == '0)
            pwm_raw = 1'b0;
        else if (duty_reg >= period_reg)
            pwm_raw = 1'b1;
        else
            pwm_raw = (counter < duty_reg) ? 1'b1 : 1'b0;
    end
 
    assign pwm_out     = pwm_raw;
    assign pwm_out_n   = ~pwm_raw;
    assign counter_out = counter;
 
    initial begin
        if (RESOLUTION != 8  && RESOLUTION != 10 &&
            RESOLUTION != 12 && RESOLUTION != 16) begin
            $error("[pwm_channel] Invalid RESOLUTION=%0d.", RESOLUTION);
            $finish;
        end
    end
 
endmodule

