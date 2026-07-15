// pcie_cfg_test.sv — Config space enumeration test (all 64 DWORDs, write+read)
`ifndef PCIE_CFG_TEST_SV
`define PCIE_CFG_TEST_SV
`include "uvm_macros.svh"
import uvm_pkg::*;

class pcie_cfg_test extends pcie_base_test;
    `uvm_component_utils(pcie_cfg_test)

    pcie_cfg_seq cfg_seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        cfg_seq = pcie_cfg_seq::type_id::create("cfg_seq");
        cfg_seq.start_reg     = 0;
        cfg_seq.end_reg       = 63;      // All 256 bytes = 64 DWORDs
        cfg_seq.do_write_first= 1;       // Write then read-back each reg
        cfg_seq.randomize_tc  = 1;       // TC0/TC1 random mix
        cfg_seq.start(env.agent.seqr);
        #500ns;
        phase.drop_objection(this);
    endtask

endclass

`endif
