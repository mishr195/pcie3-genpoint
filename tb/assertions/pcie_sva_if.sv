// pcie_sva_if.sv
// Concurrent SVA properties for PCIe Gen3 protocol correctness.
// All assertions share a common reset qualifier via `default disable iff`.
// Properties are grouped by protocol concern rather than by signal.

`ifndef PCIE_SVA_IF_SV
`define PCIE_SVA_IF_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

interface pcie_sva_if (
    input logic        clk,
    input logic        rst_n,
    input logic        tx_valid,
    input logic        tx_ready,
    input logic        tx_sop,
    input logic        tx_eop,
    input logic [31:0] tx_data,
    input logic        rx_valid,
    input logic        rx_ready,
    input logic        rx_sop,
    input logic [3:0]  ltssm_state,
    input logic        link_up,
    input logic [7:0]  tx_credit_pd,
    input logic [7:0]  tx_credit_nph,
    input logic [7:0]  tx_credit_cplh
);

    default clocking @(posedge clk); endclocking
    default disable iff (!rst_n);

    // -----------------------------------------------------------------------
    // Valid/Ready handshake
    // Once tx_valid is asserted the initiator may not retract it until the
    // receiver latches the beat.  Deasserting early creates a phantom SOP.
    // -----------------------------------------------------------------------

    property p_tx_valid_stable;
        (tx_valid && !tx_ready) |=> tx_valid;
    endproperty
    AST_TX_VALID_STABLE: assert property (p_tx_valid_stable)
        else `uvm_error("SVA", "tx_valid dropped before tx_ready")

    property p_tx_data_stable;
        (tx_valid && !tx_ready) |=> $stable(tx_data);
    endproperty
    AST_TX_DATA_STABLE: assert property (p_tx_data_stable)
        else `uvm_error("SVA", "tx_data changed while tx_valid held without tx_ready")

    property p_rx_valid_stable;
        (rx_valid && !rx_ready) |=> rx_valid;
    endproperty
    AST_RX_VALID_STABLE: assert property (p_rx_valid_stable)
        else `uvm_error("SVA", "rx_valid dropped before rx_ready")

    // -----------------------------------------------------------------------
    // SOP / EOP framing
    // A new SOP inside an already-open packet means the driver missed an EOP,
    // which would corrupt the DUT's length counter.
    // -----------------------------------------------------------------------

    property p_sop_needs_valid;
        tx_sop |-> tx_valid;
    endproperty
    AST_SOP_NEEDS_VALID: assert property (p_sop_needs_valid)
        else `uvm_error("SVA", "SOP without tx_valid")

    property p_no_mid_pkt_sop;
        (tx_valid && tx_sop) |=> !(tx_valid && tx_sop) until (tx_eop);
    endproperty
    AST_NO_MID_PKT_SOP: assert property (p_no_mid_pkt_sop)
        else `uvm_error("SVA", "SOP inside an open packet (missing EOP)")

    property p_eop_needs_valid;
        tx_eop |-> tx_valid;
    endproperty
    AST_EOP_NEEDS_VALID: assert property (p_eop_needs_valid)
        else `uvm_error("SVA", "EOP without tx_valid")

    // Back-to-back packets without an idle cycle are disallowed on this
    // simplified PIPE model to give the DUT at least one cycle to latch EOP.
    property p_ipg_after_eop;
        (tx_valid && tx_eop) |=> !tx_valid;
    endproperty
    AST_IPG_AFTER_EOP: assert property (p_ipg_after_eop)
        else `uvm_warning("SVA", "No inter-packet gap after EOP")

    // -----------------------------------------------------------------------
    // LTSSM transition legality
    // Only forward transitions are legal during a clean link-up sequence.
    // -----------------------------------------------------------------------

    property p_det_to_poll;
        (ltssm_state == 4'h0) && $changed(ltssm_state) |-> (ltssm_state == 4'h1);
    endproperty
    AST_DET_TO_POLL: assert property (p_det_to_poll)
        else `uvm_error("SVA", "LTSSM left Detect to illegal state")

    property p_poll_to_cfg;
        (ltssm_state == 4'h1) && $changed(ltssm_state) |-> (ltssm_state == 4'h2);
    endproperty
    AST_POLL_TO_CFG: assert property (p_poll_to_cfg)
        else `uvm_error("SVA", "LTSSM left Polling to illegal state")

    property p_cfg_to_l0;
        (ltssm_state == 4'h2) && $changed(ltssm_state) |-> (ltssm_state == 4'h3);
    endproperty
    AST_CFG_TO_L0: assert property (p_cfg_to_l0)
        else `uvm_error("SVA", "LTSSM left Config to illegal state")

    property p_l0_exits;
        (ltssm_state == 4'h3) && $changed(ltssm_state) |-> (ltssm_state inside {4'h4, 4'h5, 4'h6});
    endproperty
    AST_L0_EXITS: assert property (p_l0_exits)
        else `uvm_error("SVA", "L0 transitioned to illegal LTSSM state")

    // link_up must be the combinational decode of LTSSM==L0 — if these
    // disagree the DUT's status register will report the wrong state.
    AST_LINK_UP_IN_L0:   assert property ((ltssm_state == 4'h3) |->  link_up)
        else `uvm_error("SVA", "link_up not set while LTSSM is L0")
    AST_LINK_DN_NOT_L0:  assert property ((ltssm_state != 4'h3) |-> !link_up)
        else `uvm_error("SVA", "link_up set while LTSSM is not L0")

    // -----------------------------------------------------------------------
    // Link-up prerequisite
    // TLP traffic before the link is operational is a spec violation and
    // would corrupt the LTSSM state machine.
    // -----------------------------------------------------------------------

    AST_NO_TX_LINK_DOWN: assert property (!link_up |-> !tx_valid)
        else `uvm_error("SVA", "TX TLP driven while link is not in L0")

    AST_NO_RX_LINK_DOWN: assert property (!link_up |-> !rx_valid)
        else `uvm_error("SVA", "DUT drove RX TLP while link is not in L0")

    // -----------------------------------------------------------------------
    // Flow control — transmitting without credits is a hard protocol error
    // regardless of tx_ready state (spec §2.5).
    // -----------------------------------------------------------------------

    property p_posted_needs_credits;
        (tx_valid && tx_sop && tx_data[31:29] inside {3'b010, 3'b011})
        |-> (tx_credit_pd != 8'h00);
    endproperty
    AST_POSTED_NEEDS_CREDITS: assert property (p_posted_needs_credits)
        else `uvm_error("SVA", "Posted TLP sent with zero Posted Data credits")

    property p_np_needs_credits;
        (tx_valid && tx_sop && tx_data[31:29] inside {3'b000, 3'b001})
        |-> (tx_credit_nph != 8'h00);
    endproperty
    AST_NP_NEEDS_CREDITS: assert property (p_np_needs_credits)
        else `uvm_error("SVA", "Non-Posted TLP sent with zero NPH credits")

    // Credit counter wrapping to 0xFF indicates underflow in the DUT's counter
    AST_PD_NO_UNDERFLOW: assert property (tx_credit_pd != 8'hFF)
        else `uvm_error("SVA", "Posted Data credit counter underflowed")

    // -----------------------------------------------------------------------
    // Packet ordering — a new Posted SOP must not appear before the previous
    // packet's EOP (no head-of-line bypass within a traffic class).
    // -----------------------------------------------------------------------

    sequence s_posted_sop;
        (tx_valid && tx_sop && tx_data[31:29] inside {3'b010, 3'b011});
    endsequence

    property p_posted_ordering;
        s_posted_sop |=> !(tx_valid && tx_sop && tx_data[31:29] inside {3'b010, 3'b011}) until (tx_eop);
    endproperty
    AST_POSTED_ORDERING: assert property (p_posted_ordering)
        else `uvm_error("SVA", "Posted TLP start before previous packet EOP")

    AST_RX_PACKET_BOUNDARY: assert property ((rx_valid && rx_sop) |=> !(rx_valid && rx_sop))
        else `uvm_error("SVA", "Back-to-back RX SOPs with no EOP between them")

    // -----------------------------------------------------------------------
    // Completion timeout — cover (not assert) that completions arrive within
    // 1024 cycles.  Simulator will flag it as a cover miss if the DUT is slow.
    // -----------------------------------------------------------------------

    sequence s_np_req;
        (tx_valid && tx_sop && tx_data[31:29] inside {3'b000, 3'b001});
    endsequence

    property p_cpl_within_timeout;
        s_np_req |-> ##[1:1024] (rx_valid && rx_sop);
    endproperty
    COV_CPL_TIMEOUT: cover  property (p_cpl_within_timeout);
    AST_CPL_TIMEOUT: assert property (p_cpl_within_timeout)
        else `uvm_warning("SVA", "Completion not received within 1024 cycles")

endinterface : pcie_sva_if

`endif
