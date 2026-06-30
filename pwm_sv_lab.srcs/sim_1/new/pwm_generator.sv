`timescale 1ns / 1ps
// ============================================================
// PWM Generator - 100% Compulsion Sweep Optimized
// Project  : Multi-Channel PWM CDV Environment
// ============================================================

`ifndef PWM_GENERATOR_SV
`define PWM_GENERATOR_SV

`include "pwm_transaction.sv"

class pwm_generator;

    int unsigned    num_transactions;
    int unsigned    seed;
    bit             directed_mode;
    mailbox #(pwm_transaction) gen2drv;
    event           gen_done;

    function new(mailbox #(pwm_transaction) mb, int n = 200, int s = 42);
        gen2drv          = mb;
        num_transactions = n;
        seed             = s;
        directed_mode    = 0;
    endfunction

    task run();
        run_random(); // Always run random to get baseline coverage
        if (directed_mode)
            run_directed();
        -> gen_done;
    endtask

    task run_random();
        pwm_transaction trans;
        
        // VIVADO FIX: Declare the arrays at the very top of the task!
        int phase_angles[4] = '{45, 135, 225, 315};
        int db_counts[4]    = '{0, 1, 5, 15};

        $display("[GEN] Starting RANDOM mode | transactions=%0d | seed=%0d", num_transactions, seed);

        // ----------------------------------------------------
        // 1. RANDOM PHASE (Hits the core ~90% naturally)
        // ----------------------------------------------------
        repeat (num_transactions) begin
            trans = new();
            if (!trans.randomize() with {
                inject_fault dist {1 := 15, 0 := 85};
                period inside {[50:2000]}; 
            }) begin
                $error("[GEN] Randomization FAILED");
            end
            gen2drv.put(trans);
        end

        $display("[GEN] Random phase complete. Starting BRUTE-FORCE 100%% Sweep...");

        // ----------------------------------------------------
        // 2. BRUTE-FORCE COMPULSION SWEEP (The Final 10%)
        // ----------------------------------------------------
        for (int ch = 0; ch < 4; ch++) begin
            
            // --- A: PHASE CROSS SWEEP (Guarantees 100% Phase) ---
            for (int q = 0; q < 4; q++) begin
                trans = new();
                trans.channel_id = ch;
                trans.period = 1000;
                trans.duty = 500; 
                trans.phase = phase_angles[q];
                trans.enable = 1;
                trans.db_enable = 1;
                trans.deadband_cnt = 5;
                trans.inject_fault = 0;
                gen2drv.put(trans);
            end

            // --- B: DEADBAND CROSS SWEEP (Guarantees 100% DB) ---
            for (int db = 0; db < 4; db++) begin
                trans = new();
                trans.channel_id = ch;
                trans.period = 2000;
                trans.duty = 1000;
                trans.phase = 0;
                trans.enable = 1;
                trans.db_enable = (db_counts[db] == 0) ? 0 : 1;
                trans.deadband_cnt = db_counts[db];
                trans.inject_fault = 0;
                gen2drv.put(trans);
            end

            // --- C: CORNER CASES (Guarantees 100% Corners) ---
            
            // 1. Explicit Disable Test (enable = 0)
            trans = new();
            trans.channel_id = ch;
            trans.period = 500;
            trans.duty = 250;
            trans.phase = 0;
            trans.enable = 0; 
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);

            // 2. Near 0% Duty (5% hits Bin 0 without breaking monitor)
            trans = new();
            trans.channel_id = ch;
            trans.period = 1000;
            trans.duty = 50; 
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);

            // 3. Near 100% Duty (95% hits Bin 9 without breaking monitor)
            trans = new();
            trans.channel_id = ch;
            trans.period = 1000;
            trans.duty = 950; 
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);
            
            // 4. Fast switching with NO deadband (Forces shoot_thru check)
            trans = new();
            trans.channel_id = ch;
            trans.period = 50; 
            trans.duty = 25;
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0; 
            trans.inject_fault = 0;
            gen2drv.put(trans);
        end
        
        $display("[GEN] BRUTE-FORCE Sweep complete. Generator finished.");
    endtask

    task run_directed();
        pwm_transaction trans;
        int max_period[4] = '{255, 1023, 4095, 65535};
        
        $display("[GEN] Starting DIRECTED mode for 100%% Coverage...");

        // 1. Freq Bins: very_low (<1kHz), low (1-10kHz), mid, high
        for (int ch = 0; ch < 4; ch++) begin
            // VERY LOW freq (<1kHz): Pause for 1.2ms (120,000 clocks)
            // Enable first to get a baseline edge
            trans = new();
            trans.channel_id = ch;
            trans.period = 200;
            trans.duty = 100;
            trans.enable = 1;
            gen2drv.put(trans);

            // Disable for a long wait (period 20000 -> driver waits 6*20000=120000 clocks)
            trans = new();
            trans.channel_id = ch;
            trans.period = 20000;
            trans.duty = 10000;
            trans.enable = 0;
            gen2drv.put(trans);

            // Re-enable to trigger edge
            trans = new();
            trans.channel_id = ch;
            trans.period = 200;
            trans.duty = 100;
            trans.enable = 1;
            gen2drv.put(trans);

            // LOW freq (1kHz - 10kHz): Pause for 120us (12,000 clocks)
            // Disable with period 2000 -> driver waits 6*2000=12000 clocks
            trans = new();
            trans.channel_id = ch;
            trans.period = 2000;
            trans.duty = 1000;
            trans.enable = 0;
            gen2drv.put(trans);

            // Re-enable to trigger edge
            trans = new();
            trans.channel_id = ch;
            trans.period = 200;
            trans.duty = 100;
            trans.enable = 1;
            gen2drv.put(trans);
            
            // HIGH freq (>100kHz)
            trans = new();
            trans.channel_id = ch;
            trans.period = 50;
            trans.duty = 25;
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);
        end

        // 2. Phase Cross Coverage (Q1, Q2, Q3, Q4)
        for (int ch = 0; ch < 4; ch++) begin
            int p;
            p = (max_period[ch] > 1000) ? 1000 : max_period[ch];
            for (int q = 0; q < 4; q++) begin
                trans = new();
                trans.channel_id = ch;
                trans.period = p;
                trans.duty = p / 2;
                trans.enable = 1;
                trans.db_enable = 0;
                trans.deadband_cnt = 0;
                trans.inject_fault = 0;
                if (q == 0) trans.phase = p / 8;       // Q1 (45 deg)
                if (q == 1) trans.phase = (p * 3) / 8; // Q2 (135 deg)
                if (q == 2) trans.phase = (p * 5) / 8; // Q3 (225 deg)
                if (q == 3) trans.phase = (p * 7) / 8; // Q4 (315 deg)
                gen2drv.put(trans);
            end
        end

        // 3. Deadband Coverage (none, short, med, long)
        for (int ch = 0; ch < 4; ch++) begin
            int db_vals[4] = '{0, 1, 5, 15}; // 0ns, 10ns, 50ns, 150ns
            for (int d = 0; d < 4; d++) begin
                trans = new();
                trans.channel_id = ch;
                trans.period = (max_period[ch] > 1000) ? 1000 : 250;
                trans.duty = trans.period / 2;
                trans.phase = 0;
                trans.enable = 1;
                trans.db_enable = (db_vals[d] > 0);
                trans.deadband_cnt = db_vals[d];
                trans.inject_fault = 0;
                gen2drv.put(trans);
            end
        end

        // 4. Fault Coverage (ALL 4 faults for ALL 4 channels)
        for (int ch = 0; ch < 4; ch++) begin
            for (int f = 0; f < 4; f++) begin
                trans = new();
                trans.channel_id = ch;
                trans.period = 200;
                trans.duty = 100;
                trans.phase = 0;
                trans.enable = 1;
                trans.db_enable = 0;
                trans.inject_fault = 1;
                trans.fault_type = f;
                gen2drv.put(trans);
            end
        end

        // 5. Corner Cases (0%, 100%, disable, shoot_thru)
        for (int ch = 0; ch < 4; ch++) begin
            // exact_0pct
            trans = new();
            trans.channel_id = ch;
            trans.period = 200;
            trans.duty = 0;
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);
            
            // exact_100pct
            trans = new();
            trans.channel_id = ch;
            trans.period = 200;
            trans.duty = 200;
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);

            // shoot_thru
            trans = new();
            trans.channel_id = ch;
            trans.period = 10;
            trans.duty = 5;
            trans.phase = 0;
            trans.enable = 1;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);

            // disabled
            trans = new();
            trans.channel_id = ch;
            trans.period = 200;
            trans.duty = 100;
            trans.phase = 0;
            trans.enable = 0;
            trans.db_enable = 0;
            trans.inject_fault = 0;
            gen2drv.put(trans);
        end
        
        $display("[GEN] DIRECTED Sweep complete. Generator finished.");
    endtask

endclass

`endif