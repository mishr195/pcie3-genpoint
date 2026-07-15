// pcie_endpoint.sv
// Behavioural PCIe Gen3 endpoint model.  Not cycle-accurate beyond the PIPE
// interface; the goal is correct TLP-level responses so the scoreboard and
// coverage collector see realistic traffic without needing a full RTL netlist.

`timescale 1ns/1ps

module pcie_endpoint #(
    parameter DATA_WIDTH   = 32,
    parameter NUM_LANES    = 4,
    parameter DEVICE_ID    = 16'hABCD,
    parameter VENDOR_ID    = 16'h1234,
    parameter BAR0_SIZE    = 4096,
    parameter CFG_SPACE_SZ = 256
)(
    input  logic clk,
    input  logic rst_n,

    input  logic                  tx_valid,
    input  logic                  tx_sop,
    input  logic                  tx_eop,
    input  logic [DATA_WIDTH-1:0] tx_data,
    input  logic [3:0]            tx_be,
    output logic                  tx_ready,

    output logic                  rx_valid,
    output logic                  rx_sop,
    output logic                  rx_eop,
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic [3:0]            rx_be,
    input  logic                  rx_ready,

    output logic [2:0]            tx_bar_hit,
    output logic [7:0]            tx_credit_pd,
    output logic [7:0]            tx_credit_nph,
    output logic [7:0]            tx_credit_cplh,
    output logic [3:0]            ltssm_state,
    output logic                  link_up,
    output logic [1:0]            link_speed,
    output logic [3:0]            link_width,

    input  logic                  lcrc_error_inject,
    input  logic                  ecrc_error_inject,
    input  logic                  seq_num_error
);

    // -----------------------------------------------------------------------
    // LTSSM — simplified forward-only sequence to reach L0
    // -----------------------------------------------------------------------
    typedef enum logic [3:0] {
        DETECT  = 4'h0, POLLING = 4'h1,
        CONFIG  = 4'h2, L0      = 4'h3,
        RECOV   = 4'h4, L0S     = 4'h5, L1 = 4'h6
    } ltssm_t;

    ltssm_t   ltssm_q, ltssm_d;
    logic [7:0] cnt;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin ltssm_q <= DETECT; cnt <= '0; end
        else        begin ltssm_q <= ltssm_d; cnt <= cnt + 1'b1; end

    always_comb begin
        ltssm_d = ltssm_q;
        case (ltssm_q)
            DETECT:  if (cnt >= 8'd10) ltssm_d = POLLING;
            POLLING: if (cnt >= 8'd30) ltssm_d = CONFIG;
            CONFIG:  if (cnt >= 8'd60) ltssm_d = L0;
            default: ;
        endcase
    end

    assign ltssm_state = ltssm_q;
    assign link_up     = (ltssm_q == L0);
    assign link_speed  = 2'b11;
    assign link_width  = 4'd4;

    // Advertise infinite credits on link-up — simplifies the driver model
    assign tx_credit_pd   = link_up ? 8'hFF : 8'h00;
    assign tx_credit_nph  = link_up ? 8'hFF : 8'h00;
    assign tx_credit_cplh = link_up ? 8'hFF : 8'h00;

    // -----------------------------------------------------------------------
    // PCI Type-0 config space (256 B)
    // -----------------------------------------------------------------------
    logic [7:0] cfg [0:CFG_SPACE_SZ-1];
    initial begin
        foreach (cfg[i]) cfg[i] = 8'h00;
        {cfg[1],  cfg[0] } = VENDOR_ID;
        {cfg[3],  cfg[2] } = DEVICE_ID;
        {cfg[7],  cfg[6] } = 16'h0010;  // status: cap list present
        cfg[8]  = 8'h01;                 // revision ID
        cfg[11] = 8'hFF;                 // base class: unclassified
    end

    logic [7:0] bar0 [0:BAR0_SIZE-1];
    initial foreach (bar0[i]) bar0[i] = 8'h00;

    // -----------------------------------------------------------------------
    // RX state machine — parse incoming TLP header words
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        RX_IDLE, RX_DW1, RX_DW2, RX_DW3, RX_DATA, RX_DONE
    } rx_fsm_t;

    rx_fsm_t     rx_st;
    logic [7:0]  rx_fmt_type;
    logic [9:0]  rx_len;
    logic [7:0]  rx_tag;
    logic [15:0] rx_rid;
    logic [31:0] rx_addr;
    logic [3:0]  rx_fbe;
    logic [7:0]  cpl_tag;
    logic [15:0] cpl_rid;
    logic [31:0] cpl_addr;
    logic        cpl_is_cfgrd;

    logic is_cfgrd, is_cfgwr, is_memrd, is_memwr, is_4dw_mem;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || !link_up) begin
            rx_st <= RX_IDLE;
        end else if (tx_valid && tx_ready) begin
            case (rx_st)
                RX_IDLE: if (tx_sop) begin
                    rx_fmt_type <= tx_data[31:24];
                    rx_len      <= tx_data[9:0];
                    rx_st       <= RX_DW1;
                end
                RX_DW1: begin
                    rx_rid  <= tx_data[31:16];
                    rx_tag  <= tx_data[15:8];
                    rx_fbe  <= tx_data[3:0];
                    rx_st   <= RX_DW2;
                end
                RX_DW2: begin
                    rx_addr <= tx_data;
                    rx_st   <= is_4dw_mem ? RX_DW3 :
                               ((is_memwr || is_cfgwr) ? RX_DATA : RX_DONE);
                end
                RX_DW3: begin
                    rx_st <= (is_memwr || is_cfgwr) ? RX_DATA : RX_DONE;
                end
                RX_DATA: if (tx_eop) rx_st <= RX_DONE;
                RX_DONE: rx_st <= RX_IDLE;
            endcase
        end
    end

    assign is_cfgrd = (rx_fmt_type == 8'h04);
    assign is_cfgwr = (rx_fmt_type == 8'h44);
    assign is_memrd = (rx_fmt_type == 8'h00) || (rx_fmt_type == 8'h20);
    assign is_memwr = (rx_fmt_type == 8'h40) || (rx_fmt_type == 8'h60);
    assign is_4dw_mem = (rx_fmt_type == 8'h20) || (rx_fmt_type == 8'h60);

    assign tx_bar_hit[0] = (rx_addr[31:12] == 20'h0) && (is_memrd || is_memwr);
    assign tx_bar_hit[2:1] = '0;

    // -----------------------------------------------------------------------
    // TX state machine — generate CplD for reads, Cpl for config writes
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] { TX_IDLE, TX_DW0, TX_DW1, TX_DW2, TX_DATA, TX_WAIT } tx_fsm_t;
    tx_fsm_t tx_st;
    logic    tx_cpl_has_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || !link_up) begin
            tx_st    <= TX_IDLE;
            tx_cpl_has_data <= 1'b0;
            cpl_tag  <= '0;
            cpl_rid  <= '0;
            cpl_addr <= '0;
            cpl_is_cfgrd <= 1'b0;
            rx_valid <= '0;
            rx_sop   <= '0;
            rx_eop   <= '0;
            rx_data  <= '0;
            rx_be    <= '0;
        end else begin
            case (tx_st)
                TX_IDLE: begin
                    rx_valid <= '0; rx_sop <= '0; rx_eop <= '0;
                    if (rx_st == RX_DONE && (is_cfgrd || is_memrd || is_cfgwr)) begin
                        cpl_tag  <= rx_tag;
                        cpl_rid  <= rx_rid;
                        cpl_addr <= rx_addr;
                        cpl_is_cfgrd <= is_cfgrd;
                        tx_cpl_has_data <= (is_cfgrd || is_memrd);
                        tx_st <= TX_DW0;
                    end
                end
                TX_DW0: begin
                    rx_valid <= 1; rx_sop <= 1; rx_eop <= 0;
                    rx_data  <= tx_cpl_has_data ? 32'h4A00_0001 : 32'h0A00_0000;
                    rx_be    <= 4'hF;
                    tx_st    <= TX_DW1;
                end
                TX_DW1: begin
                    rx_sop  <= 0; rx_eop <= 0;
                    rx_data <= {16'h0000, 3'b000, 1'b0, tx_cpl_has_data ? 12'd4 : 12'd0};
                    tx_st   <= TX_DW2;
                end
                TX_DW2: begin
                    rx_eop  <= !tx_cpl_has_data;
                    rx_data <= {cpl_rid, cpl_tag, 1'b0, cpl_addr[6:0]};
                    tx_st   <= tx_cpl_has_data ? TX_DATA : TX_WAIT;
                end
                TX_DATA: begin
                    rx_eop <= 1;
                    // Mux config space vs BAR0 based on the decoded request type
                    rx_data <= cpl_is_cfgrd
                        ? {cfg[cpl_addr[7:0]+3], cfg[cpl_addr[7:0]+2],
                           cfg[cpl_addr[7:0]+1], cfg[cpl_addr[7:0]]}
                        : {bar0[cpl_addr[11:0]+3], bar0[cpl_addr[11:0]+2],
                           bar0[cpl_addr[11:0]+1], bar0[cpl_addr[11:0]]};
                    tx_st <= TX_WAIT;
                end
                TX_WAIT: begin
                    rx_valid <= 0; rx_eop <= 0;
                    tx_cpl_has_data <= 1'b0;
                    tx_st    <= TX_IDLE;
                end
            endcase
        end
    end

    assign tx_ready = link_up && ((rx_st != RX_IDLE) || (tx_st == TX_IDLE));

endmodule : pcie_endpoint
