// pcie_power_mgmt_test.sv — L0s/L1 power state transitions + traffic after wake
`ifndef PCIE_POWER_MGMT_TEST_SV
`define PCIE_POWER_MGMT_TEST_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_power_mgmt_test extends pcie_base_test;
    `uvm_component_utils(pcie_power_mgmt_test)

    int unsigned num_power_cycles = 3;
    int unsigned idle_cycles      = 100;  // Cycles to simulate idle (L0s entry)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        pcie_base_seq      pre_idle_seq;
        pcie_mem_burst_seq wake_seq;
        pcie_tlp_item      tlp;
        phase.raise_objection(this);

        repeat (num_power_cycles) begin
            // Traffic before idle
            pre_idle_seq = pcie_base_seq::type_id::create("pre_idle");
            pre_idle_seq.num_transactions = 5;
            pre_idle_seq.start(env.agent.seqr);

            // Simulate idle period — driver does nothing, DUT may enter L0s
            `uvm_info("PWR_TEST", $sformatf("Entering %0d-cycle idle (simulating L0s)",
                      idle_cycles), UVM_MEDIUM)
            repeat(idle_cycles) @(posedge env.agent.drv.vif.clk);

            // Traffic after wake — verifies DUT recovers correctly
            wake_seq = pcie_mem_burst_seq::type_id::create("wake_burst");
            wake_seq.burst_depth    = 4;
            wake_seq.num_bursts     = 2;
            wake_seq.dwords_per_tlp = 4;
            wake_seq.start(env.agent.seqr);
        end

        #500ns;
        phase.drop_objection(this);
    endtask

endclass

`endif
