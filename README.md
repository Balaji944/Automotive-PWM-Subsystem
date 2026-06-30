# Scalable Safety-Critical PWM Subsystem with CDV & Fault Injection

This repository contains the RTL, advanced verification environment, and physical design metrics for an ASIL-D compliant, APB-based PWM subsystem designed for Wide Bandgap (WBG) motor control.

## Project Highlights
* **Hardware:** Scalable 4-channel SystemVerilog PWM controller with 10ns programmable hardware deadband insertion.
* **SoC Integration:** Fully packaged as an AMBA APB 3.0 compliant Xilinx Vivado IP block.
* **Verification Environment:** Object-Oriented Coverage-Driven Verification (CDV) testbench (UVM-style) utilizing Constrained Random and Directed Testing.
* **Fault Tolerance:** Automated fault injection framework detecting 100% of induced APB bus errors (Stuck-At, SEU, Wrong Address).
* **Data Analytics:** Python-based simulation log parsing and Matplotlib data visualization.

## Verification Metrics
* Functional Coverage: **100%** (via Hybrid CRV & Directed Sweeps)
* Diagnostic Coverage: **100%** (46 uniquely injected faults detected)

## Physical Design (PPA)
Synthesized on Xilinx Artix-7:
* **Area:** 578 LUTs, 638 Registers
* **Power:** 6.45 W (Unconstrained worst-case dynamic estimation)
* **Timing:** Zero WNS violations (Combinatorial paths optimized)
