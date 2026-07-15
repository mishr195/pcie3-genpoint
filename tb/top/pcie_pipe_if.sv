// pcie_pipe_if.sv
// Simplified PIPE interface between the UVM agent and the PCIe endpoint DUT.
// Only the transaction-layer-visible signals are modelled here; 8b/10b and
// elastic buffer logic live inside the DUT and are not exposed to the TB.

`ifndef PCIE_PIPE_IF_SV
`define PCIE_PIPE_IF_SV

interface pcie_pipe_if #(
    parameter DATA_WIDTH = 32,
    parameter NUM_LANES  = 4
)(
    input logic clk,
    input logic rst_n
);

    // TX path — host drives, DUT receives
    logic                   tx_valid;
    logic                   tx_sop;
    logic                   tx_eop;
    logic [DATA_WIDTH-1:0]  tx_data;
    logic [3:0]             tx_be;
    logic                   tx_ready;       // DUT back-pressure
    logic [2:0]             tx_bar_hit;
    logic [7:0]             tx_credit_pd;
    logic [7:0]             tx_credit_nph;
    logic [7:0]             tx_credit_cplh;

    // RX path — DUT drives, host receives
    logic                   rx_valid;
    logic                   rx_sop;
    logic                   rx_eop;
    logic [DATA_WIDTH-1:0]  rx_data;
    logic [3:0]             rx_be;
    logic                   rx_ready;

    // Link status
    logic [3:0]             ltssm_state;
    logic                   link_up;
    logic [1:0]             link_speed;
    logic [3:0]             link_width;

    // Fault injection — driven by error sequences only
    logic                   lcrc_error_inject;
    logic                   ecrc_error_inject;
    logic                   seq_num_error;

    // Clocking blocks keep driver and monitor sampling edges unambiguous.
    // #1step input avoids sampling the edge we just drove.
    clocking driver_cb @(posedge clk);
        default input  #1step;
        default output #1;
        output tx_valid, tx_sop, tx_eop, tx_data, tx_be, rx_ready;
        output lcrc_error_inject, ecrc_error_inject, seq_num_error;
        input  tx_ready, tx_bar_hit;
        input  tx_credit_pd, tx_credit_nph, tx_credit_cplh;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;
        input tx_valid, tx_sop, tx_eop, tx_data, tx_be, tx_ready;
        input rx_valid, rx_sop, rx_eop, rx_data, rx_be, rx_ready;
        input ltssm_state, link_up, link_speed, link_width;
    endclocking

    modport drv_mp (clocking driver_cb,  input clk, input rst_n);
    modport mon_mp (clocking monitor_cb, input clk, input rst_n);
    modport dut_mp (
        input  tx_valid, tx_sop, tx_eop, tx_data, tx_be, rx_ready,
               lcrc_error_inject, ecrc_error_inject, seq_num_error,
        output tx_ready, tx_bar_hit, tx_credit_pd, tx_credit_nph,
               tx_credit_cplh, rx_valid, rx_sop, rx_eop, rx_data,
               rx_be, ltssm_state, link_up, link_speed, link_width
    );

    // Blocks until the appropriate credit type is non-zero.
    // Per spec §2.5, transmitting without credits is a protocol violation
    // regardless of whether tx_ready is asserted.
    task automatic wait_for_tx_credits(input logic [1:0] tlp_class);
        @(posedge clk);
        case (tlp_class)
            2'b00: while (!tx_credit_pd)   @(posedge clk);
            2'b01: while (!tx_credit_nph)  @(posedge clk);
            2'b10: while (!tx_credit_cplh) @(posedge clk);
        endcase
    endtask

    task automatic apply_reset(input int unsigned cycles = 10);
        repeat(cycles) @(posedge clk);
        wait(link_up === 1'b1);
        `ifndef SYNTHESIS
            $display("[%0t][PIPE] Link UP  speed=Gen%0d  width=x%0d",
                     $time, link_speed, link_width);
        `endif
    endtask

endinterface : pcie_pipe_if

`endif
