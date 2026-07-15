// pcie_predictor.sv
// Reference model: given a stimulus TLP seen on TX, predict what the DUT
// should send back on RX.  Only non-posted and config requests generate
// completions; posted writes are fire-and-forget.

`ifndef PCIE_PREDICTOR_SV
`define PCIE_PREDICTOR_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_predictor extends uvm_component;
    `uvm_component_utils(pcie_predictor)

    uvm_analysis_imp  #(pcie_tlp_item, pcie_predictor) tx_imp;
    uvm_analysis_port #(pcie_tlp_item)                  predict_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        tx_imp     = new("tx_imp",     this);
        predict_ap = new("predict_ap", this);
    endfunction

    function void write(pcie_tlp_item req);
        pcie_tlp_item exp_cpl;

        case (req.tlp_type)

            MRD_32, MRD_64, MRDLK_32, MRDLK_64: begin
                // Memory read — expect a CplD sized to match the request length
                exp_cpl              = make_cpl(req, CPLD);
                exp_cpl.payload_len  = req.payload_len;
                exp_cpl.byte_count   = req.payload_len * 4;
                predict_ap.write(exp_cpl);
            end

            CFGRD0, CFGRD1: begin
                // Config read always returns exactly one DWORD regardless of length field
                exp_cpl              = make_cpl(req, CPLD);
                exp_cpl.payload_len  = 10'd1;
                exp_cpl.byte_count   = 12'd4;
                predict_ap.write(exp_cpl);
            end

            CFGWR0, CFGWR1: begin
                // Config write generates a Cpl (no data) to acknowledge receipt
                exp_cpl = make_cpl(req, CPL);
                predict_ap.write(exp_cpl);
            end

            default: begin
                // Malformed or poisoned TLP — DUT should respond with UR
                if (req.ep || req.inject_lcrc_error) begin
                    exp_cpl            = make_cpl(req, CPL);
                    exp_cpl.cpl_status = UR;
                    predict_ap.write(exp_cpl);
                end
                // Posted writes (MWr, Msg) — no completion expected, drop silently
            end

        endcase
    endfunction

    // Factor out the boilerplate that is common to every predicted completion
    function pcie_tlp_item make_cpl(pcie_tlp_item req, tlp_type_e cpl_type);
        pcie_tlp_item cpl = pcie_tlp_item::type_id::create("pred_cpl");
        cpl.tlp_type      = cpl_type;
        cpl.tlp_class     = COMPLETION;
        cpl.tag           = req.tag;
        cpl.requester_id  = req.requester_id;
        cpl.cpl_status    = SC;
        return cpl;
    endfunction

endclass

`endif
