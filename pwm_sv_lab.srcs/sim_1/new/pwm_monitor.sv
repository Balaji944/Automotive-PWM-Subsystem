`timescale 1ns / 1ps// ============================================================
// PWM Monitor - FIXED for xsim OOP crash
// Key fixes:
//   - Direct vif.signal access (no clocking block)
//   - Simplified edge detection using prev/curr comparison
//   - fork inside class task replaced with sequential monitors
//     (xsim OOP fork-inside-class is unreliable)
// ============================================================

`ifndef PWM_MONITOR_SV
`define PWM_MONITOR_SV

`include "pwm_transaction.sv"

// --------------------------------------------------------
// Monitor result packet
// --------------------------------------------------------
class pwm_mon_result;
    int      channel_id;
    real     measured_duty_pct;
    real     measured_period_ns;
    real     measured_freq_hz;
    real     measured_phase_deg;
    real     measured_deadband_ns;
    bit      shoot_through_detected;
    realtime capture_time;

    function new(int ch);
        channel_id   = ch;
        capture_time = $realtime;
        measured_duty_pct    = 0.0;
        measured_period_ns   = 0.0;
        measured_freq_hz     = 0.0;
        measured_phase_deg   = 0.0;
        measured_deadband_ns = 0.0;
        shoot_through_detected = 0;
    endfunction

    function void print();
        $display("[MON] CH%0d | duty=%.2f%% | freq=%.1fHz | phase=%.1fdeg | db=%.1fns | shoot=%0b",
            channel_id, measured_duty_pct, measured_freq_hz,
            measured_phase_deg, measured_deadband_ns,
            shoot_through_detected);
    endfunction
endclass

// --------------------------------------------------------
// Monitor class
// --------------------------------------------------------
class pwm_monitor;

    virtual pwm_if vif;

    mailbox #(pwm_mon_result) mon2scb;
    mailbox #(pwm_mon_result) mon2cov;

    // Per-channel tracking
    realtime rise_h[4], fall_h[4], rise_l[4];
    realtime ch0_ref_rise;
    bit      prev_h[4], prev_l[4];
    bit      first_edge[4];

    int samples_taken = 0;

    function new(virtual pwm_if vi,
                 mailbox #(pwm_mon_result) m2s,
                 mailbox #(pwm_mon_result) m2c);
        vif     = vi;
        mon2scb = m2s;
        mon2cov = m2c;
        ch0_ref_rise = 0;
        for (int i = 0; i < 4; i++) begin
            rise_h[i]    = 0;
            fall_h[i]    = 0;
            rise_l[i]    = 0;
            prev_h[i]    = 0;
            prev_l[i]    = 0;
            first_edge[i]= 1;
        end
    endfunction

    // --------------------------------------------------------
    // Single combined monitor loop - all channels in one task
    // Avoids fork-inside-class which crashes xsim
    // --------------------------------------------------------
    task run();
        bit curr_h, curr_l;
        pwm_mon_result result;
        realtime full_period, high_width;
        real duty_pct, freq_hz, phase_deg, db_ns;

        $display("[MON] Monitor started.");

        forever begin
            @(posedge vif.clk);

            // Check all 4 channels each clock cycle
            for (int ch = 0; ch < 4; ch++) begin
                curr_h = vif.pwm_h[ch];
                curr_l = vif.pwm_l[ch];

                // Shoot-through check
                if (curr_h && curr_l) begin
                    $error("[MON] SHOOT-THROUGH CH%0d @ %0t", ch, $realtime);
                end

             // Rising edge on pwm_h
                if (!prev_h[ch] && curr_h) begin
                    
                    // MUST BE HERE: Update CH0 reference immediately on EVERY edge
                    // BEFORE the first_edge check!
                    if (ch == 0) ch0_ref_rise = $realtime;

                    if (!first_edge[ch] && rise_h[ch] != 0) begin
                        // Compute metrics
                        full_period = $realtime - rise_h[ch];

                        if (fall_h[ch] > rise_h[ch])
                            high_width = fall_h[ch] - rise_h[ch];
                        else
                            high_width = 0;

                        if (full_period > 0) begin
                            duty_pct = (real'(high_width) / real'(full_period)) * 100.0;
                            freq_hz  = 1.0e9 / real'(full_period);
                        end else begin
                            duty_pct = 0.0;
                            freq_hz  = 0.0;
                        end

                        // Phase vs CH0
                        if (ch == 0) begin
                            phase_deg = 0.0;
                        end else begin
                            if (ch0_ref_rise > 0 && full_period > 0)
                                phase_deg = (real'($realtime - ch0_ref_rise) /
                                             real'(full_period)) * 360.0;
                            else
                                phase_deg = 0.0;
                        end
                        // ... rest of code

                        // Deadband
                        if (rise_l[ch] > fall_h[ch])
                            db_ns = real'(rise_l[ch] - fall_h[ch]);
                        else
                            db_ns = 0.0;

                        // Build and send result
                        result = new(ch);
                        result.measured_duty_pct    = duty_pct;
                        result.measured_period_ns   = real'(full_period);
                        result.measured_freq_hz     = freq_hz;
                        result.measured_phase_deg   = phase_deg;
                        result.measured_deadband_ns = db_ns;
                        result.shoot_through_detected = (curr_h & curr_l);

                        result.print();
                        mon2scb.put(result);
                        mon2cov.put(result);
                        samples_taken++;
                    end

                    rise_h[ch]    = $realtime;
                    first_edge[ch]= 0;
                end

                // Falling edge on pwm_h
                if (prev_h[ch] && !curr_h)
                    fall_h[ch] = $realtime;

                // Rising edge on pwm_l (for deadband)
                if (!prev_l[ch] && curr_l)
                    rise_l[ch] = $realtime;

                prev_h[ch] = curr_h;
                prev_l[ch] = curr_l;
            end
        end
    endtask

    function void report();
        $display("[MON] Total samples: %0d", samples_taken);
    endfunction

endclass

`endif