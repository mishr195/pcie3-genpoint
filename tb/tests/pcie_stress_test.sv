// pcie_stress_test.sv — Maximum throughput: high-depth bursts, all TLP types, all TCs
`ifndef PCIE_STRESS_TEST_SV
`define PCIE_STRESS_TEST_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_stress_test extends pcie_base_test;
    `uvm_component_utils(pcie_stress_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        pcie_mem_burst_seq mem_seq;
        pcie_cfg_seq       cfg_seq;
        pcie_base_seq      rand_seq;
        phase.raise_objection(this);

        // Phase 1: deep MWr bursts at max payload
        mem_seq = pcie_mem_burst_seq::type_id::create("stress_mem");
        mem_seq.burst_depth    = 32;
        mem_seq.num_bursts     = 10;
        mem_seq.dwords_per_tlp = 32;   // 128 bytes — typical MPS
        mem_seq.interleave_rd  = 0;    // Write-only for max stress
        mem_seq.start(env.agent.seqr);

        // Phase 2: config space flood
        cfg_seq = pcie_cfg_seq::type_id::create("stress_cfg");
        cfg_seq.end_reg      = 63;
        cfg_seq.do_write_first = 1;
        cfg_seq.randomize_tc   = 1;
        cfg_seq.start(env.agent.seqr);

        // Phase 3: fully random high-volume traffic
        rand_seq = pcie_base_seq::type_id::create("stress_rand");
        rand_seq.num_transactions = 200;
        rand_seq.start(env.agent.seqr);

        #2000ns;
        phase.drop_objection(this);
    endtask

endclass

`endif
