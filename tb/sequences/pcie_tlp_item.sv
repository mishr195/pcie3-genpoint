// pcie_tlp_item.sv
// TLP sequence item + shared type definitions for the PCIe Gen3 verification env.
// Spec ref: PCI Express Base Spec r3.0, Sections 2.2–2.3.

`ifndef PCIE_TLP_ITEM_SV
`define PCIE_TLP_ITEM_SV

// ---------------------------------------------------------------------------
// Package: pcie_tlp_types_pkg
// Keep all enums and helpers here so every TB layer imports the same types
// without pulling in the full sequence item class.
// ---------------------------------------------------------------------------
package pcie_tlp_types_pkg;

    // fmt[2:0] || type[4:0] packed into one byte for easy case-matching
    typedef enum logic [7:0] {
        MRD_32   = 8'h00,
        MRD_64   = 8'h20,
        MRDLK_32 = 8'h01,
        MRDLK_64 = 8'h21,
        MWR_32   = 8'h40,
        MWR_64   = 8'h60,
        IORD     = 8'h02,
        IOWR     = 8'h42,
        CFGRD0   = 8'h04,
        CFGWR0   = 8'h44,
        CFGRD1   = 8'h05,
        CFGWR1   = 8'h45,
        CPL      = 8'h0A,
        CPLD     = 8'h4A,
        CPLLK    = 8'h0B,
        CPLDLK   = 8'h4B,
        MSG      = 8'h30,
        MSGD     = 8'h70
    } tlp_type_e;

    typedef enum logic [1:0] {
        POSTED     = 2'b00,   // no completion expected
        NON_POSTED = 2'b01,   // completion required
        COMPLETION = 2'b10
    } tlp_class_e;

    // Table 2-18 — completion status field
    typedef enum logic [2:0] {
        SC  = 3'b000,
        UR  = 3'b001,
        CRS = 3'b010,
        CA  = 3'b100
    } cpl_status_e;

    typedef enum logic [2:0] {
        TC0 = 3'b000, TC1 = 3'b001, TC2 = 3'b010, TC3 = 3'b011,
        TC4 = 3'b100, TC5 = 3'b101, TC6 = 3'b110, TC7 = 3'b111
    } traffic_class_e;

    typedef enum logic [3:0] {
        LTSSM_DETECT   = 4'h0, LTSSM_POLLING  = 4'h1,
        LTSSM_CONFIG   = 4'h2, LTSSM_L0       = 4'h3,
        LTSSM_RECOVERY = 4'h4, LTSSM_L0S      = 4'h5,
        LTSSM_L1       = 4'h6, LTSSM_L2       = 4'h7,
        LTSSM_DISABLED = 4'h8, LTSSM_LOOPBACK = 4'h9,
        LTSSM_HOTRESET = 4'hA
    } ltssm_state_e;

    typedef enum logic [2:0] {
        MPS_128B  = 3'b000, MPS_256B  = 3'b001,
        MPS_512B  = 3'b010, MPS_1024B = 3'b011,
        MPS_2048B = 3'b100, MPS_4096B = 3'b101
    } max_payload_size_e;

    function automatic bit tlp_has_data(input tlp_type_e t);
        return (t inside {MWR_32, MWR_64, IOWR, CFGWR0, CFGWR1, CPLD, CPLDLK, MSGD});
    endfunction

    function automatic bit tlp_is_4dw(input tlp_type_e t);
        return (t inside {MRD_64, MRDLK_64, MWR_64});
    endfunction

endpackage : pcie_tlp_types_pkg


// ---------------------------------------------------------------------------
// Class: pcie_tlp_item
// Central transaction object. Every TB component — driver, monitor, scoreboard,
// predictor, coverage — works with this class. Keeping do_copy/do_compare
// correct here saves a lot of pain downstream.
// ---------------------------------------------------------------------------
class pcie_tlp_item extends uvm_sequence_item;

    import pcie_tlp_types_pkg::*;

    `uvm_object_utils_begin(pcie_tlp_item)
        `uvm_field_enum    (tlp_type_e,      tlp_type,      UVM_ALL_ON)
        `uvm_field_enum    (tlp_class_e,     tlp_class,     UVM_ALL_ON)
        `uvm_field_enum    (traffic_class_e, tc,            UVM_ALL_ON)
        `uvm_field_int     (tag,                            UVM_ALL_ON)
        `uvm_field_int     (requester_id,                   UVM_ALL_ON)
        `uvm_field_int     (completer_id,                   UVM_ALL_ON)
        `uvm_field_int     (payload_len,                    UVM_ALL_ON)
        `uvm_field_int     (addr_32,                        UVM_ALL_ON)
        `uvm_field_int     (addr_64,                        UVM_ALL_ON)
        `uvm_field_int     (first_dw_be,                    UVM_ALL_ON)
        `uvm_field_int     (last_dw_be,                     UVM_ALL_ON)
        `uvm_field_array_int(payload,                       UVM_ALL_ON)
        `uvm_field_enum    (cpl_status_e,    cpl_status,    UVM_ALL_ON)
        `uvm_field_int     (byte_count,                     UVM_ALL_ON)
        `uvm_field_int     (lower_addr,                     UVM_ALL_ON)
        `uvm_field_int     (attr,                           UVM_ALL_ON)
        `uvm_field_int     (ep,                             UVM_ALL_ON)
        `uvm_field_int     (td,                             UVM_ALL_ON)
        `uvm_field_int     (ecrc,                           UVM_ALL_ON)
        `uvm_field_int     (sequence_number,                UVM_ALL_ON)
        `uvm_field_int     (poison_tlp,                     UVM_ALL_ON)
        `uvm_field_int     (reg_num,                        UVM_ALL_ON)
        `uvm_field_int     (bus_num,                        UVM_ALL_ON)
        `uvm_field_int     (dev_num,                        UVM_ALL_ON)
        `uvm_field_int     (func_num,                       UVM_ALL_ON)
        `uvm_field_int     (inject_lcrc_error,              UVM_ALL_ON)
        `uvm_field_int     (inject_ecrc_error,              UVM_ALL_ON)
    `uvm_object_utils_end

    // DW0 fields
    rand tlp_type_e      tlp_type;
    rand tlp_class_e     tlp_class;
    rand traffic_class_e tc;
    rand bit             td;
    rand bit             ep;
    rand bit [1:0]       attr;
    rand bit [9:0]       payload_len;

    // DW1 fields
    rand bit [15:0]      requester_id;
    rand bit  [7:0]      tag;
    rand bit  [3:0]      first_dw_be;
    rand bit  [3:0]      last_dw_be;

    // Address
    rand bit [31:0]      addr_32;
    rand bit [63:0]      addr_64;

    // Payload
    rand bit [31:0]      payload [];

    // Config TLP DW2 fields
    rand bit [7:0]       bus_num;
    rand bit [4:0]       dev_num;
    rand bit [2:0]       func_num;
    rand bit [9:0]       reg_num;

    // Completion-specific fields
    rand cpl_status_e    cpl_status;
    rand bit [15:0]      completer_id;
    rand bit [11:0]      byte_count;
    rand bit  [6:0]      lower_addr;

    // Set by the error injection sequence, not randomized in normal traffic
    bit [11:0]           sequence_number;
    bit                  poison_tlp;
    bit [31:0]           ecrc;
    bit                  inject_lcrc_error;
    bit                  inject_ecrc_error;

    // -----------------------------------------------------------------------
    // Constraints
    // -----------------------------------------------------------------------

    // Enforce Posted/NP/Completion class based on TLP type — the class field
    // drives credit-type selection in the driver, so it must stay consistent.
    constraint c_class_consistency {
        if (tlp_type inside {MWR_32, MWR_64, MSG, MSGD})
            tlp_class == POSTED;
        else if (tlp_type inside {MRD_32, MRD_64, MRDLK_32, MRDLK_64,
                                   IORD, IOWR, CFGRD0, CFGWR0, CFGRD1, CFGWR1})
            tlp_class == NON_POSTED;
        else if (tlp_type inside {CPL, CPLD, CPLLK, CPLDLK})
            tlp_class == COMPLETION;
    }

    // Zero-length field encodes 1024 DW per spec §2.2.7.
    // Config and I/O are always exactly 1 DW; reads carry no payload at all.
    constraint c_payload_len {
        if (tlp_type inside {MRD_32, MRD_64, MRDLK_32, MRDLK_64, IORD, CFGRD0, CFGRD1, CPL})
            payload_len == 10'd0;
        else if (tlp_type inside {CFGWR0, CFGWR1, IOWR})
            payload_len == 10'd1;
        else if (tlp_type inside {MWR_32, MWR_64})
            payload_len inside {[10'd1 : 10'd32]};
        else if (tlp_type inside {CPLD, CPLDLK})
            payload_len inside {[10'd1 : 10'd32]};
    }

    // DWORD alignment is mandatory; natural alignment enforced for bursts
    // to avoid crossing 4KB boundaries at the completer.
    constraint c_addr_alignment {
        addr_32[1:0] == 2'b00;
        addr_64[1:0] == 2'b00;
        if (payload_len > 10'd16) addr_32[5:0] == 6'h00;
        if (payload_len > 10'd16) addr_64[5:0] == 6'h00;
    }

    constraint c_addr_range {
        if (tlp_type inside {CFGRD0, CFGWR0, CFGRD1, CFGWR1})
            addr_32[31:12] == 20'h0;
        else if (tlp_type inside {MRD_32, MWR_32, MRDLK_32})
            addr_32 inside {[32'h0000_0000 : 32'hFFFF_FFFC]};
        else if (tlp_type inside {MRD_64, MWR_64, MRDLK_64})
            addr_64[63:32] inside {[32'h0 : 32'h0000_000F]};
    }

    // Spec §2.2.9: byte enables must be contiguous — no holes.
    // last_dw_be must be 0 for single-DW transfers to avoid completer ambiguity.
    constraint c_byte_enables {
        if (payload_len inside {10'd0, 10'd1}) last_dw_be == 4'b0000;
        if (tlp_type inside {CFGRD0, CFGWR0, CFGRD1, CFGWR1, IORD, IOWR})
            last_dw_be == 4'b0000;

        first_dw_be inside {
            4'b1111, 4'b1110, 4'b1100, 4'b1000,
            4'b0111, 4'b0011, 4'b0001,
            4'b0110, 4'b0010, 4'b0100, 4'b0000
        };

        if (payload_len > 10'd1) {
            last_dw_be inside {
                4'b1111, 4'b1110, 4'b1100, 4'b1000,
                4'b0111, 4'b0011, 4'b0001,
                4'b0110, 4'b0010, 4'b0100
            };
        }

        if (tlp_type inside {MWR_32, MWR_64, IOWR, CFGWR0, CFGWR1})
            first_dw_be != 4'b0000;
    }

    constraint c_payload_array_size { payload.size() == payload_len; }

    constraint c_tag_range { tag inside {[8'h00 : 8'hFF]}; }

    constraint c_reg_num {
        if (tlp_type inside {CFGRD0, CFGWR0, CFGRD1, CFGWR1}) {
            reg_num[1:0] == 2'b00;
            reg_num inside {[10'd0 : 10'd255]};
        }
    }

    // byte_count tracks remaining bytes in a split completion sequence;
    // it must be at least as large as what this TLP delivers.
    constraint c_cpl_byte_count {
        if (tlp_type inside {CPL, CPLD, CPLLK, CPLDLK}) {
            byte_count inside {[12'd1 : 12'd4096]};
            byte_count >= (payload_len * 10'd4);
            lower_addr[1:0] == 2'b00;
        }
    }

    // TC0 dominates real PCIe traffic; TC7 is isochronous and nearly never used.
    constraint c_tc_dist {
        tc dist { TC0 := 60, TC1 := 15, TC2 := 10, TC3 := 5,
                  TC4 := 4,  TC5 := 3,  TC6 := 2,  TC7 := 1 };
    }

    // Biased toward memory traffic to stress the BAR decoder and completion path.
    constraint c_type_dist {
        tlp_type dist {
            MRD_32 := 20, MRD_64 := 10, MWR_32 := 25, MWR_64 := 10,
            CFGRD0 := 10, CFGWR0 := 10, CFGRD1 := 3,  CFGWR1 := 3,
            CPL    := 2,  CPLD   := 5,  IORD   := 1,  IOWR   := 1
        };
    }

    constraint c_ecrc_td    { if (!td) inject_ecrc_error == 0; }

    constraint c_bdf_range {
        bus_num  inside {[8'h00 : 8'hFF]};
        dev_num  inside {[5'h00 : 5'h1F]};
        func_num inside {[3'h0  : 3'h7 ]};
    }

    // Root complex always lives at bus 0, device 0; function varies.
    constraint c_requester_id {
        requester_id[15:8] == 8'h00;
        requester_id[7:3]  == 5'h00;
        requester_id[2:0]  inside {3'h0, 3'h1};
    }

    // -----------------------------------------------------------------------
    function new(string name = "pcie_tlp_item");
        super.new(name);
    endfunction

    function void post_randomize();
        // Solver ordering can occasionally leave the array stale — force sync.
        if (payload.size() != payload_len) begin
            payload = new[payload_len];
            foreach (payload[i]) payload[i] = $urandom();
        end
        poison_tlp = ep;
    endfunction

    function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_string   ("TLP Type",   tlp_type.name());
        printer.print_string   ("TLP Class",  tlp_class.name());
        printer.print_string   ("TC",         tc.name());
        printer.print_field_int("Tag",        tag,          8,  UVM_HEX);
        printer.print_field_int("ReqID",      requester_id, 16, UVM_HEX);
        printer.print_field_int("Len(DW)",    payload_len,  10, UVM_DEC);
        printer.print_field_int("1st BE",     first_dw_be,  4,  UVM_BIN);
        printer.print_field_int("Last BE",    last_dw_be,   4,  UVM_BIN);
        if (tlp_type inside {MRD_32, MWR_32, CFGRD0, CFGWR0, IORD, IOWR})
            printer.print_field_int("Addr32", addr_32, 32, UVM_HEX);
        else if (tlp_type inside {MRD_64, MWR_64})
            printer.print_field_int("Addr64", addr_64, 64, UVM_HEX);
        if (tlp_type inside {CFGRD0, CFGWR0, CFGRD1, CFGWR1}) begin
            printer.print_field_int("Bus",  bus_num,  8,  UVM_HEX);
            printer.print_field_int("Dev",  dev_num,  5,  UVM_HEX);
            printer.print_field_int("Func", func_num, 3,  UVM_HEX);
            printer.print_field_int("Reg",  reg_num,  10, UVM_HEX);
        end
        if (tlp_type inside {CPL, CPLD}) begin
            printer.print_string   ("CplStatus",  cpl_status.name());
            printer.print_field_int("ByteCount",  byte_count, 12, UVM_DEC);
        end
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        pcie_tlp_item rhs_cast;
        bit           ok;
        ok = super.do_compare(rhs, comparer);
        if (!$cast(rhs_cast, rhs))
            `uvm_error("TLP_ITEM", "do_compare: type mismatch")
        ok &= comparer.compare_field_int("tlp_type",    int'(this.tlp_type),    int'(rhs_cast.tlp_type),    8);
        ok &= comparer.compare_field_int("payload_len", this.payload_len,        rhs_cast.payload_len,        10);
        ok &= comparer.compare_field_int("tag",         this.tag,                rhs_cast.tag,                8);
        ok &= comparer.compare_field_int("first_dw_be", this.first_dw_be,        rhs_cast.first_dw_be,        4);
        if (this.payload.size() == rhs_cast.payload.size()) begin
            foreach (this.payload[i])
                ok &= comparer.compare_field_int($sformatf("payload[%0d]", i),
                          this.payload[i], rhs_cast.payload[i], 32);
        end else begin
            comparer.print_msg($sformatf("payload size mismatch: exp=%0d got=%0d",
                               this.payload.size(), rhs_cast.payload.size()));
            ok = 0;
        end
        return ok;
    endfunction

    function void do_copy(uvm_object rhs);
        pcie_tlp_item src;
        super.do_copy(rhs);
        if (!$cast(src, rhs))
            `uvm_fatal("TLP_ITEM", "do_copy: type mismatch")
        this.tlp_type          = src.tlp_type;
        this.tlp_class         = src.tlp_class;
        this.tc                = src.tc;
        this.tag               = src.tag;
        this.requester_id      = src.requester_id;
        this.completer_id      = src.completer_id;
        this.payload_len       = src.payload_len;
        this.addr_32           = src.addr_32;
        this.addr_64           = src.addr_64;
        this.first_dw_be       = src.first_dw_be;
        this.last_dw_be        = src.last_dw_be;
        this.payload           = new[src.payload.size()](src.payload);
        this.cpl_status        = src.cpl_status;
        this.byte_count        = src.byte_count;
        this.lower_addr        = src.lower_addr;
        this.td                = src.td;
        this.ep                = src.ep;
        this.attr              = src.attr;
        this.sequence_number   = src.sequence_number;
        this.poison_tlp        = src.poison_tlp;
        this.ecrc              = src.ecrc;
        this.inject_lcrc_error = src.inject_lcrc_error;
        this.inject_ecrc_error = src.inject_ecrc_error;
        this.bus_num           = src.bus_num;
        this.dev_num           = src.dev_num;
        this.func_num          = src.func_num;
        this.reg_num           = src.reg_num;
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("[%s | TC=%s | tag=0x%02h | len=%0dDW",
                      tlp_type.name(), tc.name(), tag, payload_len);
        case (tlp_type)
            MRD_32, MWR_32, MRDLK_32:
                s = {s, $sformatf(" | addr=0x%08h", addr_32)};
            MRD_64, MWR_64, MRDLK_64:
                s = {s, $sformatf(" | addr=0x%016h", addr_64)};
            CFGRD0, CFGWR0, CFGRD1, CFGWR1:
                s = {s, $sformatf(" | bdf=%02h:%02h.%01h reg=0x%03h",
                                  bus_num, dev_num, func_num, reg_num)};
            CPL, CPLD:
                s = {s, $sformatf(" | sts=%s bcnt=%0d", cpl_status.name(), byte_count)};
        endcase
        s = {s, $sformatf(" | fbe=%04b lbe=%04b]", first_dw_be, last_dw_be)};
        return s;
    endfunction

endclass : pcie_tlp_item

`endif
