// pcie_agent_pkg.sv — Compile-order package for all agent files
`ifndef PCIE_AGENT_PKG_SV
`define PCIE_AGENT_PKG_SV

package pcie_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import pcie_tlp_types_pkg::*;

    `include "pcie_tlp_item.sv"
    `include "pcie_sequencer.sv"
    `include "pcie_driver.sv"
    `include "pcie_monitor.sv"
    `include "pcie_agent.sv"
endpackage

`endif
