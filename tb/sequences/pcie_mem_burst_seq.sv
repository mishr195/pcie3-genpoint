// pcie_mem_burst_seq.sv
// Drives back-to-back MWr bursts followed by optional MRd readbacks.
// The read-back phase catches address-mapping bugs that don't show up
// when writes are sent in isolation.

`ifndef PCIE_MEM_BURST_SEQ_SV
`define PCIE_MEM_BURST_SEQ_SV
`include "uvm_macros.svh"
import uvm_pkg::*;
import pcie_tlp_types_pkg::*;

class pcie_mem_burst_seq extends pcie_base_seq;
    `uvm_object_utils(pcie_mem_burst_seq)

    int unsigned burst_depth    = 8;
    int unsigned num_bursts     = 4;
    bit [31:0]   base_addr      = 32'h0000_0000;
    int unsigned dwords_per_tlp = 4;
    bit          use_64bit_addr = 0;
    bit          interleave_rd  = 1;

    function new(string name = "pcie_mem_burst_seq");
        super.new(name);
    endfunction

    task body();
        pcie_tlp_item tlp;
        bit [31:0]    cur_addr;

        repeat (num_bursts) begin
            cur_addr = base_addr;

            repeat (burst_depth) begin
                `uvm_create(tlp)
                assert(tlp.randomize() with {
                    tlp_type    == (use_64bit_addr ? MWR_64 : MWR_32);
                    payload_len == dwords_per_tlp;
                    addr_32     == cur_addr;
                    first_dw_be == 4'hF;
                    last_dw_be  == (payload_len > 1 ? 4'hF : 4'h0);
                }) else `uvm_fatal("MEM_BURST", "MWr randomize failed")
                `uvm_send(tlp)
                cur_addr += dwords_per_tlp * 4;
            end

            if (interleave_rd) begin
                cur_addr = base_addr;
                repeat (burst_depth) begin
                    `uvm_create(tlp)
                    assert(tlp.randomize() with {
                        tlp_type    == (use_64bit_addr ? MRD_64 : MRD_32);
                        payload_len == dwords_per_tlp;
                        addr_32     == cur_addr;
                        first_dw_be == 4'hF;
                        last_dw_be  == 4'h0;
                    }) else `uvm_fatal("MEM_BURST", "MRd randomize failed")
                    `uvm_send(tlp)
                    cur_addr += dwords_per_tlp * 4;
                end
            end
        end
    endtask

endclass

`endif
