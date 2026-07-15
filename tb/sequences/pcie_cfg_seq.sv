// pcie_cfg_seq.sv
// Walks the config space register map using CfgRd0/CfgWr0.
// With do_write_first=1 this exercises the write→readback path that
// exposes sticky-bit bugs in writable config registers.

`ifndef PCIE_CFG_SEQ_SV
`define PCIE_CFG_SEQ_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_cfg_seq extends pcie_base_seq;
    `uvm_object_utils(pcie_cfg_seq)

    int unsigned start_reg      = 0;
    int unsigned end_reg        = 63;   // 64 DWORDs = 256 bytes
    bit          do_write_first = 0;
    bit          randomize_tc   = 0;

    function new(string name = "pcie_cfg_seq");
        super.new(name);
    endfunction

    task body();
        pcie_tlp_item tlp;

        for (int r = start_reg; r <= end_reg; r++) begin

            if (do_write_first) begin
                `uvm_create(tlp)
                assert(tlp.randomize() with {
                    tlp_type    == CFGWR0;
                    reg_num     == (r * 4);
                    bus_num     == 8'h00;
                    dev_num     == 5'h00;
                    func_num    == 3'h0;
                    first_dw_be == 4'hF;
                    last_dw_be  == 4'h0;
                    tc          inside {TC0, TC1};
                }) else `uvm_fatal("CFG_SEQ", "CfgWr randomize failed")
                `uvm_send(tlp)
            end

            `uvm_create(tlp)
            assert(tlp.randomize() with {
                tlp_type    == CFGRD0;
                reg_num     == (r * 4);
                bus_num     == 8'h00;
                dev_num     == 5'h00;
                func_num    == 3'h0;
                first_dw_be == 4'hF;
                last_dw_be  == 4'h0;
                if (randomize_tc) tc inside {TC0, TC1, TC2};
                else              tc == TC0;
            }) else `uvm_fatal("CFG_SEQ", "CfgRd randomize failed")
            `uvm_send(tlp)
        end
    endtask

endclass

`endif
