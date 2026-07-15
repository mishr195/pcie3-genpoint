// pcie_error_test.sv — Fault injection test: cycles through all error modes
`ifndef PCIE_ERROR_TEST_SV
`define PCIE_ERROR_TEST_SV
`include "uvm_macros.svh"
import uvm_pkg::*;

class pcie_error_test extends pcie_base_test;
    `uvm_component_utils(pcie_error_test)

    pcie_error_injection_seq err_seq;
    error_type_e             error_mode = ERR_LCRC;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        // Cycle through all error modes: each run exercises a different fault
        for (int i = 0; i < 6; i++) begin
            err_seq = pcie_error_injection_seq::type_id::create("err_seq");
            err_seq.error_mode    = error_type_e'(i);
            err_seq.num_error_tlps= 3;
            err_seq.num_good_tlps = 2;
            err_seq.start(env.agent.seqr);
        end
        #500ns;
        phase.drop_objection(this);
    endtask

endclass

`endif
