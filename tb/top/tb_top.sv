// tb_top.sv
// Testbench top — wires the DUT, interfaces, and SVA module together,
// generates clocks, and hands control to the UVM test layer.
// 250 MHz matches the PIPE clock for a Gen3 x4 link (8 GT/s per lane).

`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;


module tb_top;

    // Clock and reset
    localparam CLK_HALF_NS = 2;   // 250 MHz
    localparam RST_CYCLES  = 20;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always  #CLK_HALF_NS clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat(RST_CYCLES) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    // Interface instances
    pcie_pipe_if #(.DATA_WIDTH(32), .NUM_LANES(4)) pipe_if (.clk(clk), .rst_n(rst_n));

    // DUT
    pcie_endpoint #(
        .DATA_WIDTH (32),
        .NUM_LANES  (4),
        .DEVICE_ID  (16'hABCD),
        .VENDOR_ID  (16'h1234)
    ) u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .tx_valid          (pipe_if.tx_valid),
        .tx_sop            (pipe_if.tx_sop),
        .tx_eop            (pipe_if.tx_eop),
        .tx_data           (pipe_if.tx_data),
        .tx_be             (pipe_if.tx_be),
        .tx_ready          (pipe_if.tx_ready),
        .rx_valid          (pipe_if.rx_valid),
        .rx_sop            (pipe_if.rx_sop),
        .rx_eop            (pipe_if.rx_eop),
        .rx_data           (pipe_if.rx_data),
        .rx_be             (pipe_if.rx_be),
        .rx_ready          (pipe_if.rx_ready),
        .tx_bar_hit        (pipe_if.tx_bar_hit),
        .tx_credit_pd      (pipe_if.tx_credit_pd),
        .tx_credit_nph     (pipe_if.tx_credit_nph),
        .tx_credit_cplh    (pipe_if.tx_credit_cplh),
        .ltssm_state       (pipe_if.ltssm_state),
        .link_up           (pipe_if.link_up),
        .link_speed        (pipe_if.link_speed),
        .link_width        (pipe_if.link_width),
        .lcrc_error_inject (pipe_if.lcrc_error_inject),
        .ecrc_error_inject (pipe_if.ecrc_error_inject),
        .seq_num_error     (pipe_if.seq_num_error)
    );

    // SVA monitor taps directly onto the same nets as the DUT ports
    pcie_sva_if u_sva (
        .clk            (clk),
        .rst_n          (rst_n),
        .tx_valid       (pipe_if.tx_valid),
        .tx_ready       (pipe_if.tx_ready),
        .tx_sop         (pipe_if.tx_sop),
        .tx_eop         (pipe_if.tx_eop),
        .tx_data        (pipe_if.tx_data),
        .rx_valid       (pipe_if.rx_valid),
        .rx_ready       (pipe_if.rx_ready),
        .rx_sop         (pipe_if.rx_sop),
        .ltssm_state    (pipe_if.ltssm_state),
        .link_up        (pipe_if.link_up),
        .tx_credit_pd   (pipe_if.tx_credit_pd),
        .tx_credit_nph  (pipe_if.tx_credit_nph),
        .tx_credit_cplh (pipe_if.tx_credit_cplh)
    );

    initial begin
        uvm_config_db #(virtual pcie_pipe_if)::set(null, "uvm_test_top", "vif",     pipe_if);
        uvm_config_db #(virtual pcie_sva_if) ::set(null, "uvm_test_top", "sva_vif", u_sva);
        run_test();
    end

    // Hard cap — prevents runaway simulations from consuming farm time
    initial begin
        #10_000_000ns;
        `uvm_fatal("TIMEOUT", "10ms watchdog expired")
    end

    initial begin
        if ($test$plusargs("DUMP_WAVES")) begin
            $dumpfile("pcie_tb.vcd");
            $dumpvars(0, tb_top);
        end
    end

endmodule : tb_top
