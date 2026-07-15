// pcie_base_test.sv — Base test: sanity random traffic (20 transactions)
`ifndef PCIE_BASE_TEST_SV
`define PCIE_BASE_TEST_SV
`include "uvm_macros.svh"
import uvm_pkg::*;

class pcie_base_test extends uvm_test;
    `uvm_component_utils(pcie_base_test)

    pcie_env       env;
    pcie_base_seq  seq;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = pcie_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        seq = pcie_base_seq::type_id::create("seq");
        seq.num_transactions = 20;
        seq.start(env.agent.seqr);
        #100ns;
        phase.drop_objection(this);
    endtask

endclass

`endif
