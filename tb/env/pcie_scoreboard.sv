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
    pcie_tlp_item expected_q[$];
    pcie_tlp_item actual_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        pred_fifo   = new("pred_fifo",   this);
        actual_fifo = new("actual_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
        fork
            collect_expected();
            collect_actual();
        join
    endtask

    task collect_expected();
        pcie_tlp_item pred, actual;
        int idx;
        forever begin
            pred_fifo.get(pred);
            idx = find_actual_by_tag(pred.tag);
            if (idx >= 0) begin
                actual = actual_q[idx];
                actual_q.delete(idx);
                check_tlp(pred, actual);
            end else begin
                expected_q.push_back(pred);
            end
        end
    endtask

    task collect_actual();
        pcie_tlp_item pred, actual;
        int idx;
        forever begin
            actual_fifo.get(actual);
            idx = find_expected_by_tag(actual.tag);
            if (idx >= 0) begin
                pred = expected_q[idx];
                expected_q.delete(idx);
                check_tlp(pred, actual);
            end else begin
                actual_q.push_back(actual);
            end
        end
    endtask

    function int find_expected_by_tag(bit [7:0] tag);
        foreach (expected_q[i])
            if (expected_q[i].tag == tag)
                return i;
        return -1;
    endfunction

    function int find_actual_by_tag(bit [7:0] tag);
        foreach (actual_q[i])
            if (actual_q[i].tag == tag)
                return i;
        return -1;
    endfunction

    task wait_for_idle(int unsigned timeout_ns = 1000);
        int unsigned idle_ns = 0;
        repeat (timeout_ns) begin
            if ((expected_q.size() == 0) && (actual_q.size() == 0) &&
                (pred_fifo.used() == 0) && (actual_fifo.used() == 0)) begin
                idle_ns++;
                if (idle_ns >= 20)
                    return;
            end else begin
                idle_ns = 0;
            end
            #1ns;
        end
        `uvm_warning("SCB", $sformatf("Timed out waiting for scoreboard idle: exp_q=%0d act_q=%0d pred_fifo=%0d act_fifo=%0d",
                     expected_q.size(), actual_q.size(), pred_fifo.used(), actual_fifo.used()))
    endtask

    function void check_tlp(pcie_tlp_item pred, pcie_tlp_item actual);
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
        foreach (expected_q[i]) begin
            fail_cnt++;
            `uvm_error("SCB", $sformatf("[MISS #%0d] No actual completion for expected %s",
                       fail_cnt, expected_q[i].convert2string()))
        end
        foreach (actual_q[i]) begin
            fail_cnt++;
            `uvm_error("SCB", $sformatf("[UNEXP #%0d] Unexpected actual completion %s",
                       fail_cnt, actual_q[i].convert2string()))
        end
        `uvm_info("SCB", $sformatf(
            "\n  ===== Scoreboard =====\n  Checked : %0d\n  Pass    : %0d\n  Fail    : %0d\n  =====================",
            total, pass_cnt, fail_cnt), UVM_NONE)
        if (fail_cnt > 0)
            `uvm_error("SCB", "SIMULATION FAILED")
        else
            `uvm_info("SCB", "SIMULATION PASSED", UVM_NONE)
    endfunction

endclass

`endif
