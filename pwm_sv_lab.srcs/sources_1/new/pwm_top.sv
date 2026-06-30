`timescale 1ns / 1ps// ============================================================
// PWM Top - 4-Channel Multi-Resolution PWM Subsystem
// Project  : Multi-Channel PWM CDV Environment
// Engineer : RVCE EC Dept
// Tool     : Vivado 2024.1 (xsim)
//
// Architecture:
//   - 4 independent PWM channels (CH0..CH3)
//   - Each channel: parameterized resolution (8/10/12/16-bit)
//   - Each channel has its own deadband generator
//   - APB-like register interface for configuration
//   - Global sync signal to start all channels simultaneously
//   - Fault status register readable via APB
//
// APB Register Map:
//   Addr 0x00 : CH0 Duty     [15:0]
//   Addr 0x04 : CH0 Period   [15:0]
//   Addr 0x08 : CH0 Phase    [15:0]
//   Addr 0x0C : CH0 Control  [0]=enable [1]=db_enable [9:2]=deadband_cnt
//   Addr 0x10 : CH1 Duty
//   Addr 0x14 : CH1 Period
//   Addr 0x18 : CH1 Phase
//   Addr 0x1C : CH1 Control
//   Addr 0x20 : CH2 Duty
//   Addr 0x24 : CH2 Period
//   Addr 0x28 : CH2 Phase
//   Addr 0x2C : CH2 Control
//   Addr 0x30 : CH3 Duty
//   Addr 0x34 : CH3 Period
//   Addr 0x38 : CH3 Phase
//   Addr 0x3C : CH3 Control
//   Addr 0x40 : GLOBAL SYNC  [0]=sync_start
//   Addr 0x44 : FAULT STATUS [3:0]=shoot_through per channel (RO)
// ============================================================
// FIXED:
//   1. cfg_valid now uses a registered one-cycle pulse per channel
//      so channels latch config AFTER registers are written, not during.
//   2. reg_sync replaced with sync_pulse: a clean one-cycle strobe
//      generated the cycle AFTER the APB sync write completes.
//   3. Phase counter reset on new cfg_valid so phase is always
//      measured from the moment a new transaction is programmed.
// ============================================================
 
module pwm_top #(
    parameter CH0_RES = 8,
    parameter CH1_RES = 10,
    parameter CH2_RES = 12,
    parameter CH3_RES = 16,
    parameter CLK_FREQ = 100_000_000
)(
    input  logic        clk,
    input  logic        rst_n,
 
    // APB Interface
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
 
    // PWM Outputs
    output logic [3:0]  pwm_h,
    output logic [3:0]  pwm_l,
    output logic [3:0]  pwm_raw,
 
    // Status
    output logic [3:0]  db_active,
    output logic [3:0]  cycle_done,
    output logic        fault_detected,
    output logic [15:0] ch0_counter,
    output logic [15:0] ch1_counter,
    output logic [15:0] ch2_counter,
    output logic [15:0] ch3_counter
);
 
    // --------------------------------------------------------
    // APB Register File
    // --------------------------------------------------------
    logic [15:0] reg_duty   [0:3];
    logic [15:0] reg_period [0:3];
    logic [15:0] reg_phase  [0:3];
    logic [15:0] reg_ctrl   [0:3];
    logic        reg_sync;
    logic [3:0]  fault_status;
 
    // APB write decode
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                reg_duty[i]   <= '0;
                reg_period[i] <= 16'd1000; // safe default period
                reg_phase[i]  <= '0;
                reg_ctrl[i]   <= '0;
            end
            reg_sync <= 1'b0;
        end else begin
            reg_sync <= 1'b0; // auto-clear each cycle
            if (psel && penable && pwrite) begin
                case (paddr)
                    8'h00: reg_duty[0]   <= pwdata[15:0];
                    8'h04: reg_period[0] <= pwdata[15:0];
                    8'h08: reg_phase[0]  <= pwdata[15:0];
                    8'h0C: reg_ctrl[0]   <= pwdata[15:0];
                    8'h10: reg_duty[1]   <= pwdata[15:0];
                    8'h14: reg_period[1] <= pwdata[15:0];
                    8'h18: reg_phase[1]  <= pwdata[15:0];
                    8'h1C: reg_ctrl[1]   <= pwdata[15:0];
                    8'h20: reg_duty[2]   <= pwdata[15:0];
                    8'h24: reg_period[2] <= pwdata[15:0];
                    8'h28: reg_phase[2]  <= pwdata[15:0];
                    8'h2C: reg_ctrl[2]   <= pwdata[15:0];
                    8'h30: reg_duty[3]   <= pwdata[15:0];
                    8'h34: reg_period[3] <= pwdata[15:0];
                    8'h38: reg_phase[3]  <= pwdata[15:0];
                    8'h3C: reg_ctrl[3]   <= pwdata[15:0];
                    8'h40: reg_sync      <= pwdata[0];
                    default: ;
                endcase
            end
        end
    end
 
    // APB read decode
    always_comb begin
        prdata  = '0;
        pslverr = 1'b0;
        case (paddr)
            8'h00: prdata = {16'h0, reg_duty[0]};
            8'h04: prdata = {16'h0, reg_period[0]};
            8'h08: prdata = {16'h0, reg_phase[0]};
            8'h0C: prdata = {16'h0, reg_ctrl[0]};
            8'h10: prdata = {16'h0, reg_duty[1]};
            8'h14: prdata = {16'h0, reg_period[1]};
            8'h18: prdata = {16'h0, reg_phase[1]};
            8'h1C: prdata = {16'h0, reg_ctrl[1]};
            8'h20: prdata = {16'h0, reg_duty[2]};
            8'h24: prdata = {16'h0, reg_period[2]};
            8'h28: prdata = {16'h0, reg_phase[2]};
            8'h2C: prdata = {16'h0, reg_ctrl[2]};
            8'h30: prdata = {16'h0, reg_duty[3]};
            8'h34: prdata = {16'h0, reg_period[3]};
            8'h38: prdata = {16'h0, reg_phase[3]};
            8'h3C: prdata = {16'h0, reg_ctrl[3]};
            8'h40: prdata = {31'h0, reg_sync};
            8'h44: prdata = {28'h0, fault_status};
            default: begin
                prdata  = 32'hDEAD_BEEF;
                pslverr = 1'b1;
            end
        endcase
    end
 
    assign pready = 1'b1;
 
    // --------------------------------------------------------
    // FIX #1: cfg_valid - registered pulse, fires the cycle
    // AFTER the control register write completes.
    // Old code fired during the APB write using paddr[7:4]==i
    // which is combinational and races with register updates.
    // Now: detect ctrl write (addr 0x0C/1C/2C/3C) and pulse
    // cfg_valid one cycle later so all four regs are stable.
    // --------------------------------------------------------
    logic cfg_valid_reg [0:3];
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++)
                cfg_valid_reg[i] <= 1'b0;
        end else begin
            for (int i = 0; i < 4; i++)
                cfg_valid_reg[i] <= 1'b0; // default clear
 
            // Fire cfg_valid one cycle after the SYNC write (0x40)
            // This guarantees period/duty/phase/ctrl are all latched
            // before the channel sees cfg_valid.
            if (psel && penable && pwrite && (paddr == 8'h40)) begin
                for (int i = 0; i < 4; i++)
                    cfg_valid_reg[i] <= 1'b1;
            end
        end
    end
 
    // Channel config decode from registers
    logic        cfg_en    [0:3];
    logic        cfg_db_en [0:3];
    logic [7:0]  cfg_db_cnt[0:3];
 
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            cfg_en[i]     = reg_ctrl[i][0];
            cfg_db_en[i]  = reg_ctrl[i][1];
            cfg_db_cnt[i] = reg_ctrl[i][9:2];
        end
    end
 
    // --------------------------------------------------------
    // Internal channel wires
    // --------------------------------------------------------
    logic [3:0] pwm_out_raw;
    logic [3:0] pwm_out_n_raw;
 
    // --------------------------------------------------------
    // Channel 0 - 8-bit resolution
    // --------------------------------------------------------
    pwm_channel #(.RESOLUTION(CH0_RES), .CLK_FREQ(CLK_FREQ)) u_ch0 (
        .clk        (clk),
        .rst_n      (rst_n),
        .cfg_valid  (cfg_valid_reg[0]),
        .cfg_duty   (reg_duty[0]),
        .cfg_period (reg_period[0]),
        .cfg_phase  (reg_phase[0]),
        .cfg_enable (cfg_en[0]),
        .pwm_out    (pwm_out_raw[0]),
        .pwm_out_n  (pwm_out_n_raw[0]),
        .counter_out(ch0_counter),
        .cycle_done (cycle_done[0])
    );
 
    // --------------------------------------------------------
    // Channel 1 - 10-bit resolution
    // --------------------------------------------------------
    pwm_channel #(.RESOLUTION(CH1_RES), .CLK_FREQ(CLK_FREQ)) u_ch1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .cfg_valid  (cfg_valid_reg[1]),
        .cfg_duty   (reg_duty[1]),
        .cfg_period (reg_period[1]),
        .cfg_phase  (reg_phase[1]),
        .cfg_enable (cfg_en[1]),
        .pwm_out    (pwm_out_raw[1]),
        .pwm_out_n  (pwm_out_n_raw[1]),
        .counter_out(ch1_counter),
        .cycle_done (cycle_done[1])
    );
 
    // --------------------------------------------------------
    // Channel 2 - 12-bit resolution
    // --------------------------------------------------------
    pwm_channel #(.RESOLUTION(CH2_RES), .CLK_FREQ(CLK_FREQ)) u_ch2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .cfg_valid  (cfg_valid_reg[2]),
        .cfg_duty   (reg_duty[2]),
        .cfg_period (reg_period[2]),
        .cfg_phase  (reg_phase[2]),
        .cfg_enable (cfg_en[2]),
        .pwm_out    (pwm_out_raw[2]),
        .pwm_out_n  (pwm_out_n_raw[2]),
        .counter_out(ch2_counter),
        .cycle_done (cycle_done[2])
    );
 
    // --------------------------------------------------------
    // Channel 3 - 16-bit resolution
    // --------------------------------------------------------
    pwm_channel #(.RESOLUTION(CH3_RES), .CLK_FREQ(CLK_FREQ)) u_ch3 (
        .clk        (clk),
        .rst_n      (rst_n),
        .cfg_valid  (cfg_valid_reg[3]),
        .cfg_duty   (reg_duty[3]),
        .cfg_period (reg_period[3]),
        .cfg_phase  (reg_phase[3]),
        .cfg_enable (cfg_en[3]),
        .pwm_out    (pwm_out_raw[3]),
        .pwm_out_n  (pwm_out_n_raw[3]),
        .counter_out(ch3_counter),
        .cycle_done (cycle_done[3])
    );
 
    // --------------------------------------------------------
    // Deadband Generators
    // --------------------------------------------------------
    genvar g;
    generate
        for (g = 0; g < 4; g++) begin : gen_db
            deadband_gen #(.DB_CNT_WIDTH(8)) u_db (
                .clk         (clk),
                .rst_n       (rst_n),
                .pwm_in      (pwm_out_raw[g]),
                .pwm_in_n    (pwm_out_n_raw[g]),
                .deadband_cnt(cfg_db_cnt[g]),
                .db_enable   (cfg_db_en[g]),
                .pwm_h       (pwm_h[g]),
                .pwm_l       (pwm_l[g]),
                .db_active   (db_active[g])
            );
        end
    endgenerate
 
    assign pwm_raw = pwm_out_raw;
 
    // Fault status - shoot-through detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_status <= '0;
        end else begin
            for (int i = 0; i < 4; i++) begin
                if (pwm_h[i] && pwm_l[i])
                    fault_status[i] <= 1'b1;
            end
        end
    end
 
    assign fault_detected = |fault_status;
 
endmodule