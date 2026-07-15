// pcie_scoreboard.sv
// Compares predicted completions (from the reference model) against what the
// DUT actually drove on the RX path.  Two separate TLM FIFOs decouple the
// producer and consumer timing — the predictor can write before the DUT
// responds without blocking.

`ifndef PCIE_SCOREBOARD_SV
`define PCIE_SCOREBOARD_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(pcie_scoreboard)

    uvm_tlm_analysis_fifo #(pcie_tlp_item) pred_fifo;
    uvm_tlm_analysis_fifo #(pcie_tlp_item) actual_fifo;

    int unsigned pass_cnt;
    int unsigned fail_cnt;
    int unsigned total;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        pred_fifo   = new("pred_fifo",   this);
        actual_fifo = new("actual_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
        pcie_tlp_item pred, actual;
        forever begin
            pred_fifo.get(pred);
            actual_fifo.get(actual);
            check(pred, actual);
        end
    endtask

    function void check(pcie_tlp_item pred, pcie_tlp_item actual);
        string mismatches;
        bit    ok = 1;
        total++;

        if (pred.tlp_type !== actual.tlp_type) begin
            mismatches = {mismatches, $sformatf("\n  tlp_type : exp=%s  got=%s",
                          pred.tlp_type.name(), actual.tlp_type.name())};
            ok = 0;
        end
        if (pred.tag !== actual.tag) begin
            mismatches = {mismatches, $sformatf("\n  tag      : exp=0x%02h  got=0x%02h",
                          pred.tag, actual.tag)};
            ok = 0;
        end
        if (pred.tlp_type inside {CPL, CPLD} && pred.cpl_status !== actual.cpl_status) begin
            mismatches = {mismatches, $sformatf("\n  status   : exp=%s  got=%s",
                          pred.cpl_status.name(), actual.cpl_status.name())};
            ok = 0;
        end
        if (pred.payload_len !== actual.payload_len) begin
            mismatches = {mismatches, $sformatf("\n  len      : exp=%0d  got=%0d",
                          pred.payload_len, actual.payload_len)};
            ok = 0;
        end

        if (ok) begin
            pass_cnt++;
            `uvm_info("SCB", $sformatf("[PASS #%0d] %s", pass_cnt, actual.convert2string()), UVM_HIGH)
        end else begin
            fail_cnt++;
            `uvm_error("SCB", $sformatf("[FAIL #%0d] %s%s", fail_cnt, actual.tlp_type.name(), mismatches))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf(
            "\n  ===== Scoreboard =====\n"
            "  Checked : %0d\n"
            "  Pass    : %0d\n"
            "  Fail    : %0d\n"
            "  =====================",
            total, pass_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0)
            `uvm_error("SCB", "SIMULATION FAILED")
        else
            `uvm_info("SCB", "SIMULATION PASSED", UVM_NONE)
    endfunction

endclass

`endif
