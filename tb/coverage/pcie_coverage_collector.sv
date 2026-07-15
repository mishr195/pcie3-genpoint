// pcie_coverage_collector.sv
// Samples functional coverage across 12 covergroups spanning TLP type,
// payload size, traffic class, byte enables, completion status, address
// range, tag utilization, ordering, flow control, LTSSM transitions,
// error injection, and burst depth.

`ifndef PCIE_COVERAGE_COLLECTOR_SV
`define PCIE_COVERAGE_COLLECTOR_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)

class pcie_coverage_collector extends uvm_subscriber #(pcie_tlp_item);
    `uvm_component_utils(pcie_coverage_collector)

    uvm_analysis_imp_tx #(pcie_tlp_item, pcie_coverage_collector) tx_imp;
    uvm_analysis_imp_rx #(pcie_tlp_item, pcie_coverage_collector) rx_imp;

    pcie_tlp_item cur_tx;
    pcie_tlp_item cur_rx;

    // Tracking state for ordering/burst metrics
    int unsigned  consecutive_posted_count;
    bit           credit_near_zero;
    ltssm_state_e prev_ltssm, curr_ltssm;
    int unsigned  same_type_burst_count;
    tlp_type_e    burst_tlp_type;
    tlp_type_e    last_tlp_type;

    // CG1 — which TLP types actually fire
    covergroup cg_tlp_type;
        cp_type: coverpoint cur_tx.tlp_type {
            bins mem_rd[]  = {MRD_32, MRD_64};
            bins mem_wr[]  = {MWR_32, MWR_64};
            bins cfg_rd[]  = {CFGRD0, CFGRD1};
            bins cfg_wr[]  = {CFGWR0, CFGWR1};
            bins cpl_nd    = {CPL};
            bins cpl_d     = {CPLD};
            bins io_ops[]  = {IORD, IOWR};
            bins msg_ops[] = {MSG, MSGD};
            ignore_bins locked = {MRDLK_32, MRDLK_64, CPLLK, CPLDLK};
        }
        cp_class: coverpoint cur_tx.tlp_class {
            bins posted   = {POSTED};
            bins np       = {NON_POSTED};
            bins cpl      = {COMPLETION};
        }
    endgroup

    // CG2 — payload size matters for MPS compliance checking
    covergroup cg_payload_cross;
        cp_len: coverpoint cur_tx.payload_len {
            bins zero    = {0};
            bins s1_4    = {[1:4]};
            bins s5_32   = {[5:32]};
            bins s33_128 = {[33:128]};
            bins s129_256= {[129:256]};
            ignore_bins huge = {[257:1023]};
        }
        cp_grp: coverpoint cur_tx.tlp_type {
            bins rd  = {MRD_32, MRD_64};
            bins wr  = {MWR_32, MWR_64};
            bins cfg = {CFGRD0, CFGWR0, CFGRD1, CFGWR1};
            bins cpl = {CPL, CPLD};
        }
        cx: cross cp_len, cp_grp;
    endgroup

    // CG3 — high TC bins are rare; ignore_bins prevents artificial miss
    covergroup cg_traffic_class;
        cp_tc: coverpoint cur_tx.tc {
            bins tc_lo[] = {TC0, TC1, TC2, TC3};
            bins tc_hi[] = {TC4, TC5, TC6, TC7};
        }
        cp_td: coverpoint cur_tx.td {
            bins clean  = {0};
            bins digest = {1};
        }
        cx: cross cp_tc, cp_td {
            ignore_bins hi_with_digest = binsof(cp_tc.tc_hi) && binsof(cp_td.digest);
        }
    endgroup

    // CG4 — illegal_bins catches non-contiguous BE patterns that should
    // have been filtered by the constraint solver
    covergroup cg_byte_enables;
        cp_fbe: coverpoint cur_tx.first_dw_be {
            bins all_b  = {4'b1111};
            bins u3     = {4'b1110};
            bins u2     = {4'b1100};
            bins msb    = {4'b1000};
            bins l3     = {4'b0111};
            bins l2     = {4'b0011};
            bins lsb    = {4'b0001};
            bins mid2a  = {4'b0110};
            bins b2     = {4'b0010};
            bins b3     = {4'b0100};
            bins zero   = {4'b0000};
            illegal_bins holes = {4'b1010, 4'b0101, 4'b1001, 4'b1011, 4'b1101};
        }
        cp_lbe: coverpoint cur_tx.last_dw_be {
            bins all_b  = {4'b1111};
            bins zero   = {4'b0000};
            bins partial[] = {4'b1110, 4'b1100, 4'b1000, 4'b0111, 4'b0011, 4'b0001};
        }
        cx: cross cp_fbe, cp_lbe;
    endgroup

    // CG5 — CA with data is spec-unusual; mark as ignorable
    covergroup cg_cpl_status;
        cp_sts: coverpoint cur_rx.cpl_status {
            bins sc  = {SC};
            bins ur  = {UR};
            bins crs = {CRS};
            bins ca  = {CA};
        }
        cp_type: coverpoint cur_rx.tlp_type {
            bins no_data = {CPL};
            bins data    = {CPLD};
        }
        cx: cross cp_sts, cp_type {
            ignore_bins ca_d = binsof(cp_sts.ca) && binsof(cp_type.data);
        }
    endgroup

    // CG6
    covergroup cg_addr_range;
        cp_region: coverpoint cur_tx.addr_32 {
            bins bar0   = {[32'h0000_0000 : 32'h0000_0FFF]};
            bins low    = {[32'h0001_0000 : 32'h000F_FFFF]};
            bins mid    = {[32'h0010_0000 : 32'h0FFF_FFFF]};
            bins high   = {[32'h1000_0000 : 32'hFFFF_FFFC]};
            ignore_bins unaligned = {[32'h1:32'h3]};
        }
        cp_width: coverpoint cur_tx.tlp_type {
            bins a32 = {MRD_32, MWR_32, MRDLK_32};
            bins a64 = {MRD_64, MWR_64, MRDLK_64};
            bins cfg = {CFGRD0, CFGWR0, CFGRD1, CFGWR1};
        }
    endgroup

    // CG7 — extended tag (bit 7 set) requires a Device Control register write
    covergroup cg_tag_utilization;
        cp_tag: coverpoint cur_tx.tag {
            bins lo  = {[8'h00 : 8'h0F]};
            bins mid = {[8'h10 : 8'h7F]};
            bins ext = {[8'h80 : 8'hFF]};
        }
    endgroup

    // CG8 — back-to-back posted traffic stresses the ordering logic
    covergroup cg_posted_ordering;
        cp_run: coverpoint consecutive_posted_count {
            bins none  = {0};
            bins one   = {1};
            bins few   = {[2:4]};
            bins many  = {[5:8]};
            bins flood = {[9:$]};
        }
    endgroup

    // CG9
    covergroup cg_flow_control;
        cp_cls: coverpoint cur_tx.tlp_class {
            bins posted = {POSTED};
            bins np     = {NON_POSTED};
            bins cpl    = {COMPLETION};
        }
        cp_stress: coverpoint credit_near_zero {
            bins normal    = {0};
            bins near_zero = {1};
        }
        cx: cross cp_cls, cp_stress;
    endgroup

    // CG10 — only legal forward transitions are expected bins; anything else
    // would also be caught by the LTSSM SVA assertions
    covergroup cg_ltssm_transitions;
        cp_from: coverpoint prev_ltssm {
            bins detect   = {LTSSM_DETECT};
            bins polling  = {LTSSM_POLLING};
            bins cfg      = {LTSSM_CONFIG};
            bins l0       = {LTSSM_L0};
            bins recovery = {LTSSM_RECOVERY};
            bins l0s      = {LTSSM_L0S};
            bins l1       = {LTSSM_L1};
        }
        cp_to: coverpoint curr_ltssm {
            bins detect   = {LTSSM_DETECT};
            bins polling  = {LTSSM_POLLING};
            bins cfg      = {LTSSM_CONFIG};
            bins l0       = {LTSSM_L0};
            bins recovery = {LTSSM_RECOVERY};
            bins l0s      = {LTSSM_L0S};
            bins l1       = {LTSSM_L1};
        }
        cx: cross cp_from, cp_to {
            bins det_poll  = binsof(cp_from.detect)   && binsof(cp_to.polling);
            bins poll_cfg  = binsof(cp_from.polling)  && binsof(cp_to.cfg);
            bins cfg_l0    = binsof(cp_from.cfg)      && binsof(cp_to.l0);
            bins l0_rec    = binsof(cp_from.l0)       && binsof(cp_to.recovery);
            bins l0_l0s    = binsof(cp_from.l0)       && binsof(cp_to.l0s);
            bins l0s_l0    = binsof(cp_from.l0s)      && binsof(cp_to.l0);
            bins l0_l1     = binsof(cp_from.l0)       && binsof(cp_to.l1);
            bins rec_l0    = binsof(cp_from.recovery) && binsof(cp_to.l0);
            illegal_bins no_retreat = binsof(cp_from.detect) && binsof(cp_to.detect);
        }
    endgroup

    // CG11
    covergroup cg_error_injection;
        cp_lcrc: coverpoint cur_tx.inject_lcrc_error { bins off={0}; bins on={1}; }
        cp_ecrc: coverpoint cur_tx.inject_ecrc_error { bins off={0}; bins on={1}; }
        cp_ep:   coverpoint cur_tx.ep               { bins clean={0}; bins poison={1}; }
        cx: cross cp_lcrc, cp_ecrc, cp_ep;
    endgroup

    // CG12 — deep same-type bursts surface ordering and credit-return bugs
    covergroup cg_burst_depth;
        cp_depth: coverpoint same_type_burst_count {
            bins one  = {1};
            bins two  = {2};
            bins b4   = {[3:4]};
            bins b8   = {[5:8]};
            bins b16  = {[9:16]};
            bins deep = {[17:$]};
        }
        cp_btype: coverpoint burst_tlp_type {
            bins wr  = {MWR_32, MWR_64};
            bins rd  = {MRD_32, MRD_64};
            bins cfg = {CFGRD0, CFGWR0};
            bins cpl = {CPLD};
        }
        cx: cross cp_depth, cp_btype;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_tlp_type          = new();
        cg_payload_cross     = new();
        cg_traffic_class     = new();
        cg_byte_enables      = new();
        cg_cpl_status        = new();
        cg_addr_range        = new();
        cg_tag_utilization   = new();
        cg_posted_ordering   = new();
        cg_flow_control      = new();
        cg_ltssm_transitions = new();
        cg_error_injection   = new();
        cg_burst_depth       = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        tx_imp = new("tx_imp", this);
        rx_imp = new("rx_imp", this);
    endfunction

    function void write_tx(pcie_tlp_item tlp);
        cur_tx = tlp;
        consecutive_posted_count = (tlp.tlp_class == POSTED) ?
                                    consecutive_posted_count + 1 : 0;
        if (tlp.tlp_type == last_tlp_type) begin
            same_type_burst_count++;
        end else begin
            same_type_burst_count = 1;
            burst_tlp_type = tlp.tlp_type;
        end
        last_tlp_type = tlp.tlp_type;

        cg_tlp_type.sample();
        cg_payload_cross.sample();
        cg_traffic_class.sample();
        cg_byte_enables.sample();
        cg_addr_range.sample();
        cg_tag_utilization.sample();
        cg_posted_ordering.sample();
        cg_flow_control.sample();
        cg_error_injection.sample();
        cg_burst_depth.sample();
    endfunction

    function void write_rx(pcie_tlp_item tlp);
        cur_rx = tlp;
        cg_cpl_status.sample();
    endfunction

    function void write(pcie_tlp_item t); endfunction  // required by base class

    function void sample_ltssm(ltssm_state_e prev, ltssm_state_e curr);
        prev_ltssm = prev;
        curr_ltssm = curr;
        cg_ltssm_transitions.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf(
            "\n  ===== Coverage Summary =====\n"
            "  CG1  TLP Types        : %5.1f%%\n"
            "  CG2  Payload x Type   : %5.1f%%\n"
            "  CG3  Traffic Class    : %5.1f%%\n"
            "  CG4  Byte Enables     : %5.1f%%\n"
            "  CG5  Cpl Status       : %5.1f%%\n"
            "  CG6  Addr Range       : %5.1f%%\n"
            "  CG7  Tag Utilization  : %5.1f%%\n"
            "  CG8  Posted Ordering  : %5.1f%%\n"
            "  CG9  Flow Control     : %5.1f%%\n"
            "  CG10 LTSSM Transitions: %5.1f%%\n"
            "  CG11 Error Injection  : %5.1f%%\n"
            "  CG12 Burst Depth      : %5.1f%%\n"
            "  ============================",
            cg_tlp_type.get_coverage(),
            cg_payload_cross.get_coverage(),
            cg_traffic_class.get_coverage(),
            cg_byte_enables.get_coverage(),
            cg_cpl_status.get_coverage(),
            cg_addr_range.get_coverage(),
            cg_tag_utilization.get_coverage(),
            cg_posted_ordering.get_coverage(),
            cg_flow_control.get_coverage(),
            cg_ltssm_transitions.get_coverage(),
            cg_error_injection.get_coverage(),
            cg_burst_depth.get_coverage()
        ), UVM_NONE)
    endfunction

endclass

`endif
