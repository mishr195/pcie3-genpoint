// pcie_error_injection_seq.sv
// Injects protocol faults to verify the DUT's error-handling path.
// Clean TLPs are interleaved before each fault so the DUT is in a known
// good state when the error arrives — avoids masking one fault with another.

`ifndef PCIE_ERROR_INJECTION_SEQ_SV
`define PCIE_ERROR_INJECTION_SEQ_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

typedef enum {
    ERR_LCRC,
    ERR_ECRC,
    ERR_POISON,
    ERR_BAD_BE,
    ERR_ZERO_LEN,
    ERR_MALFORMED
} error_type_e;

class pcie_error_injection_seq extends pcie_base_seq;
    `uvm_object_utils(pcie_error_injection_seq)

    error_type_e error_mode     = ERR_LCRC;
    int unsigned num_error_tlps = 5;
    int unsigned num_good_tlps  = 3;

    function new(string name = "pcie_error_injection_seq");
        super.new(name);
    endfunction

    task body();
        pcie_tlp_item tlp;

        repeat (num_error_tlps) begin

            // Establish baseline traffic so the scoreboard has clean state
            repeat (num_good_tlps) begin
                `uvm_create(tlp)
                assert(tlp.randomize() with {
                    tlp_type inside {MWR_32, CFGRD0};
                    inject_lcrc_error == 0;
                    inject_ecrc_error == 0;
                    ep                == 0;
                }) else `uvm_fatal("ERR_SEQ", "good TLP randomize failed")
                `uvm_send(tlp)
            end

            `uvm_create(tlp)
            case (error_mode)
                ERR_LCRC: begin
                    assert(tlp.randomize() with {
                        tlp_type          == MWR_32;
                        inject_lcrc_error == 1;
                        inject_ecrc_error == 0;
                    }) else `uvm_fatal("ERR_SEQ", "LCRC inject randomize failed")
                end
                ERR_ECRC: begin
                    // TD must be 1 for the endpoint to check ECRC at all
                    assert(tlp.randomize() with {
                        tlp_type          == MWR_32;
                        td                == 1;
                        inject_ecrc_error == 1;
                        inject_lcrc_error == 0;
                    }) else `uvm_fatal("ERR_SEQ", "ECRC inject randomize failed")
                end
                ERR_POISON: begin
                    assert(tlp.randomize() with {
                        tlp_type inside {MWR_32, MWR_64};
                        ep == 1;
                    }) else `uvm_fatal("ERR_SEQ", "poison inject randomize failed")
                end
                ERR_BAD_BE: begin
                    assert(tlp.randomize() with {
                        tlp_type    == MWR_32;
                        payload_len == 1;
                    }) else `uvm_fatal("ERR_SEQ", "bad BE base randomize failed")
                    // Force a non-contiguous BE after solving — the constraint
                    // solver would never produce this naturally, which is the point.
                    tlp.first_dw_be = 4'b1010;
                end
                ERR_ZERO_LEN: begin
                    assert(tlp.randomize() with {
                        tlp_type    == MWR_32;
                        payload_len == 0;
                        first_dw_be == 4'hF;
                    }) else `uvm_fatal("ERR_SEQ", "zero-len inject randomize failed")
                end
                ERR_MALFORMED: begin
                    // MRDLK to anything other than the root complex is malformed
                    assert(tlp.randomize() with {
                        tlp_type == MRDLK_32;
                    }) else `uvm_fatal("ERR_SEQ", "malformed TLP randomize failed")
                end
            endcase

            `uvm_info("ERR_SEQ", $sformatf("Injecting %s", error_mode.name()), UVM_MEDIUM)
            `uvm_send(tlp)
        end
    endtask

endclass

`endif
