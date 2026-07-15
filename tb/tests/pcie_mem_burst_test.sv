// pcie_mem_burst_test.sv — Parametrized memory burst: varies depth, size, 64-bit addr
`ifndef PCIE_MEM_BURST_TEST_SV
`define PCIE_MEM_BURST_TEST_SV
`include "uvm_macros.svh"
import uvm_pkg::*;

class pcie_mem_burst_test extends pcie_base_test;
    `uvm_component_utils(pcie_mem_burst_test)

    pcie_mem_burst_seq mem_seq;

    // Knobs set from command-line via uvm_cmdline_processor or default values
    int unsigned burst_depth    = 16;
    int unsigned num_bursts     = 8;
    int unsigned dwords_per_tlp = 16;   // 64 bytes per TLP
    bit          use_64bit      = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        string arg_value;
        super.build_phase(phase);
        if (uvm_cmdline_proc.get_arg_value("+burst_depth=", arg_value))
            void'($sscanf(arg_value, "%d", burst_depth));
        if (uvm_cmdline_proc.get_arg_value("+num_bursts=", arg_value))
            void'($sscanf(arg_value, "%d", num_bursts));
        if (uvm_cmdline_proc.get_arg_value("+dw_per_tlp=", arg_value))
            void'($sscanf(arg_value, "%d", dwords_per_tlp));
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        mem_seq = pcie_mem_burst_seq::type_id::create("mem_seq");
        mem_seq.burst_depth    = burst_depth;
        mem_seq.num_bursts     = num_bursts;
        mem_seq.dwords_per_tlp = dwords_per_tlp;
        mem_seq.use_64bit_addr = use_64bit;
        mem_seq.base_addr      = 32'h0000_0000;
        mem_seq.interleave_rd  = 1;
        mem_seq.start(env.agent.seqr);
        #1000ns;
        phase.drop_objection(this);
    endtask

endclass

`endif
