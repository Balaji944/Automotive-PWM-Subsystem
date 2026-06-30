`timescale 1ns / 1ps
// ============================================================
// Deadband Generator
// Project  : Multi-Channel PWM CDV Environment
// Engineer : RVCE EC Dept
// Tool     : Vivado 2024.1 (xsim)
//
// Purpose  : Inserts a programmable deadband (dead-time) between
//            the high-side (pwm_h) and low-side (pwm_l) outputs.
//            Prevents shoot-through in H-bridge / inverter designs.
//
// How it works:
//   - When PWM goes HIGH  → pwm_h rises immediately
//                         → pwm_l falls immediately
//   - When PWM goes LOW   → pwm_h falls immediately
//                         → pwm_l rises after deadband_cnt cycles
//   This guarantees both switches are NEVER ON simultaneously.
// ============================================================

module deadband_gen #(
    parameter DB_CNT_WIDTH = 8   // supports deadband up to 255 clocks
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // From pwm_channel
    input  logic                    pwm_in,         // raw PWM output
    input  logic                    pwm_in_n,       // complementary raw

    // Config
    input  logic [DB_CNT_WIDTH-1:0] deadband_cnt,   // deadband in clock cycles
    input  logic                    db_enable,      // 0 = bypass deadband

    // Outputs with deadband applied
    output logic                    pwm_h,          // high-side gate signal
    output logic                    pwm_l,          // low-side gate signal

    // Status
    output logic                    db_active       // high during deadband window
);

    logic pwm_h_reg;
    logic pwm_l_reg;
    logic [DB_CNT_WIDTH-1:0] counter;
    logic active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_h_reg <= 1'b0;
            pwm_l_reg <= 1'b0;
            counter   <= '0;
            active    <= 1'b0;
        end else if (!db_enable) begin
            // Bypass mode - pass through directly
            pwm_h_reg <= pwm_in;
            pwm_l_reg <= pwm_in_n;
            counter   <= '0;
            active    <= 1'b0;
        end else begin
            // High side: follows PWM_in immediately (1 cycle delayed to match register timing)
            pwm_h_reg <= pwm_in;

            if (pwm_in == 1'b1) begin
                // PWM is high -> Low side must be OFF immediately
                pwm_l_reg <= 1'b0;
                // Prepare counter for when PWM goes low
                counter   <= deadband_cnt;
                active    <= 1'b0;
            end else begin
                // PWM is low -> Wait for deadband before turning on Low side
                if (counter > 0) begin
                    counter   <= counter - 1'b1;
                    pwm_l_reg <= 1'b0;
                    active    <= 1'b1;
                end else begin
                    pwm_l_reg <= 1'b1;
                    active    <= 1'b0;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Output assignments
    // --------------------------------------------------------
    assign pwm_h     = pwm_h_reg;
    assign pwm_l     = pwm_l_reg;
    assign db_active = active;

    // --------------------------------------------------------
    // Simulation check - both outputs should NEVER be HIGH
    // --------------------------------------------------------
    // pragma translate_off
    always_ff @(posedge clk) begin
        if (pwm_h_reg && pwm_l_reg) begin
            $error("[deadband_gen] SHOOT-THROUGH DETECTED: pwm_h and pwm_l both HIGH at time %0t", $time);
        end
    end
    // pragma translate_on

endmodule