// pcie_driver.sv
// Serializes TLP sequence items onto the PIPE TX interface.
// Handles flow-control credit gating and DUT back-pressure before
// each packet, matching the ordering rules in spec §2.5.

`ifndef PCIE_DRIVER_SV
`define PCIE_DRIVER_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_driver extends uvm_driver #(pcie_tlp_item);
    `uvm_component_utils(pcie_driver)

    virtual pcie_pipe_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual pcie_pipe_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        pcie_tlp_item tlp;

        // De-assert everything on entry — avoids X-propagation during LTSSM init
        vif.driver_cb.tx_valid          <= 0;
        vif.driver_cb.tx_sop            <= 0;
        vif.driver_cb.tx_eop            <= 0;
        vif.driver_cb.tx_data           <= 0;
        vif.driver_cb.tx_be             <= 0;
        vif.driver_cb.rx_ready          <= 1;
        vif.driver_cb.lcrc_error_inject <= 0;
        vif.driver_cb.ecrc_error_inject <= 0;
        vif.driver_cb.seq_num_error     <= 0;

        @(posedge vif.clk iff (vif.link_up === 1'b1));

        forever begin
            seq_item_port.get_next_item(tlp);
            drive_tlp(tlp);
            seq_item_port.item_done();
        end
    endtask

    task drive_tlp(pcie_tlp_item tlp);
        // Credit check first — we must not exceed the advertised credit limit
        // even if the DUT is asserting tx_ready.
        gate_on_credits(tlp.tlp_class);
        @(posedge vif.clk iff (vif.driver_cb.tx_ready === 1'b1));

        vif.driver_cb.lcrc_error_inject <= tlp.inject_lcrc_error;
        vif.driver_cb.ecrc_error_inject <= tlp.inject_ecrc_error;

        // DW0 with SOP
        @(vif.driver_cb);
        vif.driver_cb.tx_valid <= 1;
        vif.driver_cb.tx_sop   <= 1;
        vif.driver_cb.tx_eop   <= 0;
        vif.driver_cb.tx_data  <= build_dw0(tlp);
        vif.driver_cb.tx_be    <= 4'hF;

        // DW1: requester ID, tag, byte enables
        @(vif.driver_cb);
        vif.driver_cb.tx_sop  <= 0;
        vif.driver_cb.tx_data <= {tlp.requester_id, tlp.tag, tlp.last_dw_be, tlp.first_dw_be};

        // DW2: address or config BDF/register
        @(vif.driver_cb);
        vif.driver_cb.tx_data <= (tlp.tlp_type inside {CFGRD0, CFGWR0, CFGRD1, CFGWR1})
                                    ? build_cfg_dw2(tlp) : tlp.addr_32;

        // DW3: upper address word — only for 4DW header types
        if (tlp_is_4dw(tlp.tlp_type)) begin
            @(vif.driver_cb);
            vif.driver_cb.tx_data <= tlp.addr_64[63:32];
        end

        // Payload — last beat gets EOP and actual byte enables
        if (tlp_has_data(tlp.tlp_type) && tlp.payload.size() > 0) begin
            foreach (tlp.payload[i]) begin
                @(vif.driver_cb);
                vif.driver_cb.tx_eop  <= (i == tlp.payload.size() - 1);
                vif.driver_cb.tx_data <= tlp.payload[i];
                vif.driver_cb.tx_be   <= (i == tlp.payload.size() - 1) ?
                                          tlp.last_dw_be : 4'hF;
            end
        end else begin
            vif.driver_cb.tx_eop <= 1;
            @(vif.driver_cb);
        end

        vif.driver_cb.tx_valid          <= 0;
        vif.driver_cb.tx_sop            <= 0;
        vif.driver_cb.tx_eop            <= 0;
        vif.driver_cb.lcrc_error_inject <= 0;
        vif.driver_cb.ecrc_error_inject <= 0;

        `uvm_info("DRV", tlp.convert2string(), UVM_HIGH)
    endtask

    // DW0 layout: {fmt[2:0], type[4:0], rsvd, TC[2:0], rsvd4, TD, EP, ATTR[1:0], rsvd2, len[9:0]}
    function logic [31:0] build_dw0(pcie_tlp_item tlp);
        return {tlp.tlp_type[7:5], tlp.tlp_type[4:0], 1'b0,
                tlp.tc[2:0], 4'b0000, tlp.td, tlp.ep, tlp.attr[1:0],
                2'b00, tlp.payload_len[9:0]};
    endfunction

    function logic [31:0] build_cfg_dw2(pcie_tlp_item tlp);
        return {tlp.bus_num, tlp.dev_num, tlp.func_num, 4'b0000, tlp.reg_num[9:2], 2'b00};
    endfunction

    // Stall until credits are available; this prevents head-of-line blocking
    // on the credit-return path from starving other traffic classes.
    task gate_on_credits(pcie_tlp_types_pkg::tlp_class_e cls);
        case (cls)
            pcie_tlp_types_pkg::POSTED:
                @(posedge vif.clk iff (vif.tx_credit_pd   !== 8'h00));
            pcie_tlp_types_pkg::NON_POSTED:
                @(posedge vif.clk iff (vif.tx_credit_nph  !== 8'h00));
            pcie_tlp_types_pkg::COMPLETION:
                @(posedge vif.clk iff (vif.tx_credit_cplh !== 8'h00));
        endcase
    endtask

endclass

`endif
