// ============================================================
// PWM Testbench Top - Full OOP Verification Environment
// ============================================================

// FIXED:
//   1. join_any → join_none so ALL threads run concurrently.
//      join_any was stopping simulation the moment the
//      generator finished, killing all other threads.
//   2. Drain time increased to 5ms (500000 clocks) to allow
//      the monitor to capture the last transaction's waveform.
//   3. gen2drv mailbox size increased to 4 to reduce blocking.
// ============================================================
`timescale 1ns/1ps
 
`include "pwm_transaction.sv"
`include "pwm_generator.sv"
`include "pwm_driver.sv"
`include "pwm_monitor.sv"
`include "pwm_scoreboard.sv"
`include "pwm_coverage.sv"
`include "pwm_fault_injector.sv"
 
module pwm_tb_top;
 
    logic clk = 0;
    always #5 clk = ~clk;   // 100MHz
    logic rst_n;
 
    pwm_if vif (.clk(clk), .rst_n(rst_n));
 
    pwm_top #(
        .CH0_RES(8), .CH1_RES(10), .CH2_RES(12), .CH3_RES(16),
        .CLK_FREQ(100_000_000)
    ) dut (
        .clk            (vif.clk),
        .rst_n          (vif.rst_n),
        .psel           (vif.psel),
        .penable        (vif.penable),
        .pwrite         (vif.pwrite),
        .paddr          (vif.paddr),
        .pwdata         (vif.pwdata),
        .prdata         (vif.prdata),
        .pready         (vif.pready),
        .pslverr        (vif.pslverr),
        .pwm_h          (vif.pwm_h),
        .pwm_l          (vif.pwm_l),
        .pwm_raw        (vif.pwm_raw),
        .db_active      (vif.db_active),
        .cycle_done     (vif.cycle_done),
        .fault_detected (vif.fault_detected),
        .ch0_counter    (vif.ch0_counter),
        .ch1_counter    (vif.ch1_counter),
        .ch2_counter    (vif.ch2_counter),
        .ch3_counter    (vif.ch3_counter)
    );
 
    pwm_assertions u_assert (
        .clk            (vif.clk),
        .rst_n          (vif.rst_n),
        .psel           (vif.psel),
        .penable        (vif.penable),
        .pwrite         (vif.pwrite),
        .paddr          (vif.paddr),
        .pready         (vif.pready),
        .pslverr        (vif.pslverr),
        .pwm_h          (vif.pwm_h),
        .pwm_l          (vif.pwm_l),
        .pwm_raw        (vif.pwm_raw),
        .db_active      (vif.db_active),
        .cycle_done     (vif.cycle_done),
        .fault_detected (vif.fault_detected),
        .ch0_counter    (vif.ch0_counter),
        .ch1_counter    (vif.ch1_counter),
        .ch2_counter    (vif.ch2_counter),
        .ch3_counter    (vif.ch3_counter)
    );
 
    // Mailboxes
    mailbox #(pwm_transaction) gen2drv;
    mailbox #(pwm_transaction) drv2scb;
    mailbox #(pwm_mon_result)  mon2scb;
    mailbox #(pwm_mon_result)  mon2cov;
    mailbox #(pwm_transaction) drv2cov;
    mailbox #(pwm_transaction) drv2fault;
    mailbox #(pwm_mon_result)  scb2fault;
 
    // Components
    pwm_generator      gen;
    pwm_driver         drv;
    pwm_monitor        mon;
    pwm_scoreboard     scb;
    pwm_coverage       cov;
    pwm_fault_injector fault_inj;
 
    initial begin
        // FIX: larger mailbox sizes prevent blocking on fast bursts
        gen2drv   = new(4);
        drv2scb   = new(4);
        mon2scb   = new(4);
        mon2cov   = new(4);
        drv2cov   = new(4);
        drv2fault = new(4);
        scb2fault = new(4);
 
        gen       = new(gen2drv, 200, 42);
        gen.directed_mode = 1;
        drv       = new(vif, gen2drv, drv2scb);
        mon       = new(vif, mon2scb, mon2cov);
        scb       = new(drv2scb, mon2scb);
        cov       = new(mon2cov);
        fault_inj = new(vif);
 
        drv.drv2cov   = drv2cov;
        drv.drv2fault = drv2fault;
        scb.scb2fault = scb2fault;
 
        $display("\n============================================================");
        $display("  PWM CDV Env - Full OOP Verification");
        $display("  200 Random Tests | Scoreboard | Coverage | Fault Injection");
        $display("============================================================\n");
 
        rst_n = 0;
        vif.psel    = 0;
        vif.penable = 0;
        vif.pwrite  = 0;
        vif.paddr   = 0;
        vif.pwdata  = 0;
 
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        $display("[TB] Reset released @ %0t\n", $realtime);
 
        // FIX: join_none so ALL threads run concurrently.
        // join_any was terminating as soon as gen.run() finished.
        fork
            begin gen.run(); $display("[TB] Generator finished.\n"); end
            begin drv.run(); end
            begin mon.run(); end
            begin scb.run(); end
            begin cov.run(); end
            begin fault_inj.monitor_slverr(); end
 
            // Route driver transactions to coverage collector
            begin
                pwm_transaction t;
                forever begin
                    drv2cov.get(t);
                    cov.sample_transaction(t);
                end
            end
 
            // Route driver fault transactions to fault log
            begin
                pwm_transaction t;
                forever begin
                    drv2fault.get(t);
                    fault_inj.log_fault(t);
                end
            end
 
            // Route scoreboard fault results to fault checker
            begin
                pwm_mon_result r;
                forever begin
                    scb2fault.get(r);
                    fault_inj.check_fault(r);
                end
            end
        join_none   // FIX: was join_any
 
        // Wait for generator to finish then drain pipeline
        @(gen.gen_done);
        $display("[TB] Waiting for pipeline to drain (5ms)...");
        repeat(500000) @(posedge clk);  // FIX: 5ms drain (was 2ms)
 
        $display("\n============================================");
        $display("            FINAL VERIFICATION REPORT");
        $display("============================================\n");
 
        drv.report();
        mon.report();
        scb.report();
        cov.report();
        fault_inj.report();
 
        $display("[TB] Simulation complete @ %0t", $realtime);
        $display("[ASSERT] Check TCL console for assertion FAIL messages\n");
        $stop;
    end
 
endmodule