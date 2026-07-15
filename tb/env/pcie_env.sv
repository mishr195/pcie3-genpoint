// pcie_env.sv — UVM Environment connecting agent, predictor, scoreboard, coverage
`ifndef PCIE_ENV_SV
`define PCIE_ENV_SV
`include "uvm_macros.svh"
import uvm_pkg::*;

class pcie_env extends uvm_env;
    `uvm_component_utils(pcie_env)

    pcie_agent              agent;
    pcie_predictor          predictor;
    pcie_scoreboard         scoreboard;
    pcie_coverage_collector coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = pcie_agent::type_id::create("agent",     this);
        predictor  = pcie_predictor::type_id::create("predictor", this);
        scoreboard = pcie_scoreboard::type_id::create("scoreboard", this);
        coverage   = pcie_coverage_collector::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // TX monitor → predictor (stimulus feeds reference model)
        agent.tx_ap.connect(predictor.tx_imp);

        // TX monitor → coverage (all TX TLPs sampled for functional coverage)
        agent.tx_ap.connect(coverage.tx_imp);

        // RX monitor → coverage (DUT responses also sampled)
        agent.rx_ap.connect(coverage.rx_imp);

        // Predictor output → scoreboard expected FIFO
        predictor.predict_ap.connect(scoreboard.pred_fifo.analysis_export);

        // RX monitor → scoreboard actual FIFO
        agent.rx_ap.connect(scoreboard.actual_fifo.analysis_export);
    endfunction

endclass

`endif
