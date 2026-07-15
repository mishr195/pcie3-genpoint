// pcie_agent.sv — UVM agent wrapping sequencer, driver, monitor
`ifndef PCIE_AGENT_SV
`define PCIE_AGENT_SV
`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum { ACTIVE, PASSIVE } agent_mode_e;

class pcie_agent extends uvm_agent;
    `uvm_component_utils(pcie_agent)

    pcie_sequencer  seqr;
    pcie_driver     drv;
    pcie_monitor    mon;

    // Expose monitor ports for env-level connections
    uvm_analysis_port #(pcie_tlp_item) tx_ap;
    uvm_analysis_port #(pcie_tlp_item) rx_ap;

    agent_mode_e mode = ACTIVE;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon  = pcie_monitor::type_id::create("mon", this);
        if (mode == ACTIVE) begin
            seqr = pcie_sequencer::type_id::create("seqr", this);
            drv  = pcie_driver::type_id::create("drv",  this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (mode == ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
        // Expose monitor's analysis ports to env
        tx_ap = mon.tx_ap;
        rx_ap = mon.rx_ap;
    endfunction

endclass

`endif
