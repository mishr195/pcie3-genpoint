// pcie_base_seq.sv
// Fully-random TLP traffic.  Derived sequences override the knobs to
// constrain traffic toward a specific protocol area.

`ifndef PCIE_BASE_SEQ_SV
`define PCIE_BASE_SEQ_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_base_seq extends uvm_sequence #(pcie_tlp_item);
    `uvm_object_utils(pcie_base_seq)

    int unsigned num_transactions = 20;
    bit          enable_cfg_rd    = 1;
    bit          enable_mem_wr    = 1;
    bit          enable_mem_rd    = 1;

    function new(string name = "pcie_base_seq");
        super.new(name);
    endfunction

    task body();
        pcie_tlp_item tlp;
        repeat (num_transactions) begin
            `uvm_create(tlp)
            if (!tlp.randomize() with {
                tlp_type inside {MRD_32, MRD_64, MWR_32, MWR_64, CFGRD0, CFGWR0};
            })
                `uvm_fatal("BASE_SEQ", "randomization failed")
            `uvm_send(tlp)
        end
    endtask

endclass

`endif
