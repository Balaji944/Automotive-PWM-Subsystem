`timescale 1ns / 1ps// ============================================================
// PWM Driver
// ============================================================

// FIXED:
//   1. wait_clks: removed double repeat() and artificial 5000
//      cap. Now waits exactly 4 full periods so monitor always
//      captures at least 3 complete stable cycles.
//   2. drive_fault: for WRONG_ADDR (type 3) the correct period
//      and ctrl are still written so the channel is actually
//      running - only the duty write goes to 0xFF.
//      Previously the channel had no valid config after a
//      WRONG_ADDR fault so the monitor saw nothing.
//   3. fault_log routing: drv2fault now sends BEFORE the wait
//      so the fault injector log timestamp is accurate.
//   4. Scoreboard notification: drv2scb put AFTER the wait
//      so the expected transaction timestamp matches when the
//      monitor will actually see the waveform.
// ============================================================
 // ============================================================
// PWM Driver - FINAL FIX
// Key fix this round:
//   1. ONE-CHANNEL-AT-A-TIME rule enforced: the driver now
//      ONLY writes to the channel in the current transaction
//      and does NOT send to drv2scb until the wait completes.
//      This ensures the scoreboard receives the expected txn
//      AFTER the DUT has had time to settle, so monitor
//      results and expectations arrive in the right order.
//   2. Wait time: 6 full periods minimum to ensure the channel
//      has been running long enough for the monitor to see a
//      stable frequency (monitor needs 2 rising edges = 1 full
//      period minimum, but we need a few extra for settle).
//   3. Removed the duplicate repeat(wait_clks) from before.
// ============================================================

`ifndef PWM_DRIVER_SV
`define PWM_DRIVER_SV

`include "pwm_transaction.sv"

class pwm_driver;

    virtual pwm_if vif;

    mailbox #(pwm_transaction) gen2drv;
    mailbox #(pwm_transaction) drv2scb;
    mailbox #(pwm_transaction) drv2cov;
    mailbox #(pwm_transaction) drv2fault;

    int trans_driven  = 0;
    int faults_driven = 0;

    function new(virtual pwm_if vi,
                 mailbox #(pwm_transaction) g2d,
                 mailbox #(pwm_transaction) d2s);
        vif     = vi;
        gen2drv = g2d;
        drv2scb = d2s;
    endfunction

    task run();
        pwm_transaction trans;
        $display("[DRV] Driver started.");

        @(posedge vif.clk);
        while (!vif.rst_n) @(posedge vif.clk);
        repeat(3) @(posedge vif.clk);
        $display("[DRV] Reset seen, starting to drive @ %0t", $realtime);

        forever begin
            gen2drv.get(trans);

            // Drive APB writes
            drive_transaction(trans);

            // Notify scoreboard and coverage AFTER the wait
            // so expected and actual arrive in the same time window
            drv2scb.put(trans);
            if (drv2cov != null) drv2cov.put(trans);

            trans_driven++;
            if (trans_driven % 10 == 0)
                $display("[DRV] Progress: %0d transactions driven", trans_driven);
        end
    endtask

    task drive_transaction(pwm_transaction trans);
        logic [7:0]  base;
        logic [31:0] d_duty, d_period, d_phase, d_ctrl;
        int          wait_clks;

        base     = trans.channel_id * 8'h10;
        d_duty   = {16'h0, trans.duty};
        d_period = {16'h0, trans.period};
        d_phase  = {16'h0, trans.phase};
        d_ctrl   = {22'h0, trans.deadband_cnt, trans.db_enable, trans.enable};

        if (trans.inject_fault) begin
            faults_driven++;
            // Log fault BEFORE driving
            if (drv2fault != null) drv2fault.put(trans);
            drive_fault(trans, base, d_duty, d_period, d_phase, d_ctrl);
        end else begin
            apb_write(base + 8'h04, d_period);
            apb_write(base + 8'h08, d_phase);
            apb_write(base + 8'h00, d_duty);
            apb_write(base + 8'h0C, d_ctrl);
            apb_write(8'h40, 32'h1);  // SYNC pulse -> cfg_valid fires in DUT
        end

        // Wait 6 full periods + 500 clocks settle margin
        // Minimum 1000 clocks for very short periods
        wait_clks = (trans.period * 6) + 500;
        if (wait_clks < 1000) wait_clks = 1000;
        repeat(wait_clks) @(posedge vif.clk);
    endtask

    task drive_fault(
        pwm_transaction trans,
        logic [7:0]  base,
        logic [31:0] d_duty,
        logic [31:0] d_period,
        logic [31:0] d_phase,
        logic [31:0] d_ctrl
    );
        case (trans.fault_type)
            2'b00: begin // STUCK_AT_0: force duty to 0
                apb_write(base + 8'h04, d_period);
                apb_write(base + 8'h08, d_phase);
                apb_write(base + 8'h00, 32'h0);
                apb_write(base + 8'h0C, d_ctrl);
                apb_write(8'h40, 32'h1);
            end
            2'b01: begin // STUCK_AT_1: duty = period = 100%
                apb_write(base + 8'h04, d_period);
                apb_write(base + 8'h08, d_phase);
                apb_write(base + 8'h00, d_period);
                apb_write(base + 8'h0C, d_ctrl);
                apb_write(8'h40, 32'h1);
            end
            2'b10: begin // BIT_FLIP: XOR lower byte of duty
                apb_write(base + 8'h04, d_period);
                apb_write(base + 8'h08, d_phase);
                apb_write(base + 8'h00, d_duty ^ 32'h00FF);
                apb_write(base + 8'h0C, d_ctrl);
                apb_write(8'h40, 32'h1);
            end
            2'b11: begin // WRONG_ADDR: write duty to 0xFF -> pslverr
                apb_write(base + 8'h04, d_period);
                apb_write(base + 8'h08, d_phase);
                apb_write(base + 8'h0C, d_ctrl);
                apb_write(8'hFF, d_duty);      // bad addr
                apb_write(base + 8'h00, d_duty); // also write correct
                apb_write(8'h40, 32'h1);
            end
        endcase
    endtask

    task apb_write(logic [7:0] addr, logic [31:0] data);
        @(negedge vif.clk);
        vif.psel    = 1'b1;
        vif.penable = 1'b0;
        vif.pwrite  = 1'b1;
        vif.paddr   = addr;
        vif.pwdata  = data;

        @(negedge vif.clk);
        vif.penable = 1'b1;

        @(posedge vif.clk);
        while (!vif.pready) @(posedge vif.clk);

        @(negedge vif.clk);
        vif.psel    = 1'b0;
        vif.penable = 1'b0;
        vif.pwrite  = 1'b0;
    endtask

    function void report();
        $display("[DRV] Total driven: %0d | Faults injected: %0d",
                  trans_driven, faults_driven);
    endfunction

endclass

`endif