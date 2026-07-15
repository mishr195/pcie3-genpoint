// pcie_monitor.sv
// Passively reconstructs TLPs from the PIPE interface.
// Runs two independent threads — one per traffic direction — so a stalled
// RX path cannot block TX capture and vice versa.

`ifndef PCIE_MONITOR_SV
`define PCIE_MONITOR_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_monitor extends uvm_monitor;
    `uvm_component_utils(pcie_monitor)

    virtual pcie_pipe_if    vif;
    uvm_analysis_port #(pcie_tlp_item) tx_ap;   // stimulus TLPs (host→DUT)
    uvm_analysis_port #(pcie_tlp_item) rx_ap;   // response TLPs (DUT→host)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        tx_ap = new("tx_ap", this);
        rx_ap = new("rx_ap", this);
        if (!uvm_config_db #(virtual pcie_pipe_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            capture_tx();
            capture_rx();
        join
    endtask

    task capture_tx();
        pcie_tlp_item tlp;
        int           dw_idx;
        bit           in_pkt;

        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.tx_valid && vif.monitor_cb.tx_ready) begin
                if (vif.monitor_cb.tx_sop) begin
                    tlp     = pcie_tlp_item::type_id::create("tx_tlp");
                    dw_idx  = 0;
                    in_pkt  = 1;
                    decode_dw0(vif.monitor_cb.tx_data, tlp);
                end else if (in_pkt) begin
                    dw_idx++;
                    case (dw_idx)
                        1: begin
                            tlp.requester_id = vif.monitor_cb.tx_data[31:16];
                            tlp.tag          = vif.monitor_cb.tx_data[15:8];
                            tlp.last_dw_be   = vif.monitor_cb.tx_data[7:4];
                            tlp.first_dw_be  = vif.monitor_cb.tx_data[3:0];
                        end
                        2: begin
                            tlp.addr_32 = vif.monitor_cb.tx_data;
                            if (tlp.tlp_type inside {CFGRD0, CFGWR0, CFGRD1, CFGWR1}) begin
                                tlp.bus_num  = vif.monitor_cb.tx_data[31:24];
                                tlp.dev_num  = vif.monitor_cb.tx_data[23:19];
                                tlp.func_num = vif.monitor_cb.tx_data[18:16];
                                tlp.reg_num  = {vif.monitor_cb.tx_data[11:2], 2'b00};
                            end
                        end
                        default: begin
                            // Accumulate payload — array grows one DW per beat
                            tlp.payload = new[tlp.payload.size() + 1](tlp.payload);
                            tlp.payload[tlp.payload.size() - 1] = vif.monitor_cb.tx_data;
                        end
                    endcase
                end
                if (in_pkt && vif.monitor_cb.tx_eop) begin
                    tx_ap.write(tlp);
                    `uvm_info("MON_TX", tlp.convert2string(), UVM_HIGH)
                    in_pkt = 0;
                end
            end
        end
    endtask

    task capture_rx();
        pcie_tlp_item tlp;
        int           dw_idx;
        bit           in_pkt;

        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.rx_valid && vif.monitor_cb.rx_ready) begin
                if (vif.monitor_cb.rx_sop) begin
                    tlp    = pcie_tlp_item::type_id::create("rx_tlp");
                    dw_idx = 0;
                    in_pkt = 1;
                    decode_dw0(vif.monitor_cb.rx_data, tlp);
                end else if (in_pkt) begin
                    dw_idx++;
                    if (dw_idx == 1) begin
                        // Completion DW1: completer ID, status, byte count
                        tlp.completer_id = vif.monitor_cb.rx_data[31:16];
                        tlp.cpl_status   = cpl_status_e'(vif.monitor_cb.rx_data[15:13]);
                        tlp.byte_count   = vif.monitor_cb.rx_data[11:0];
                    end else begin
                        tlp.payload = new[tlp.payload.size() + 1](tlp.payload);
                        tlp.payload[tlp.payload.size() - 1] = vif.monitor_cb.rx_data;
                    end
                end
                if (in_pkt && vif.monitor_cb.rx_eop) begin
                    rx_ap.write(tlp);
                    `uvm_info("MON_RX", tlp.convert2string(), UVM_HIGH)
                    in_pkt = 0;
                end
            end
        end
    endtask

    function void decode_dw0(input logic [31:0] dw0, pcie_tlp_item tlp);
        tlp.tlp_type    = tlp_type_e'(dw0[31:24]);
        tlp.tc          = traffic_class_e'(dw0[22:20]);
        tlp.td          = dw0[15];
        tlp.ep          = dw0[14];
        tlp.attr        = dw0[13:12];
        tlp.payload_len = dw0[9:0];
    endfunction

endclass

`endif
