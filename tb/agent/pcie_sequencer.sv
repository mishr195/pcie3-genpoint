// pcie_sequencer.sv — Standard UVM sequencer parameterized to TLP item
`ifndef PCIE_SEQUENCER_SV
`define PCIE_SEQUENCER_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_sequencer extends uvm_sequencer #(pcie_tlp_item);
    `uvm_component_utils(pcie_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

`endif
