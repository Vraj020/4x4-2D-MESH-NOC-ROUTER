// -----------------------------------------------------------------------
// noc_router.v
// 5-port (L,N,S,E,W) router for a 2D mesh, XY dimension-order routing.
//
// Flit format (DW = 2*AW + PW bits):
//   [DW-1 -: AW]        = dest_x
//   [DW-AW-1 -: AW]     = dest_y
//   [PW-1:0]            = payload
//
// XY algorithm (at router placed at XPOS,YPOS):
//   1. Correct X first: dest_x > XPOS -> East, dest_x < XPOS -> West
//   2. Once dest_x == XPOS, correct Y: dest_y > YPOS -> North,
//      dest_y < YPOS -> South
//   3. dest_x==XPOS && dest_y==YPOS -> Local (packet has arrived)
//
// Flow control: each input port has a single-flit register (valid_reg /
// data_reg). Routing, arbitration and the crossbar operate ONLY on the
// registered flit, never on the raw incoming wire. "in_ready" for a port
// is simply "my register is empty" - a pure state signal. This is the
// key design choice that keeps the whole mesh's ready/valid network
// free of combinational loops: a router's readiness never depends on
// what a neighbor is doing in the same cycle, only on its own state.
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module noc_router #(
    parameter XPOS = 0,
    parameter YPOS = 0,
    parameter AW   = 2,             // bits needed for x/y coordinate (mesh<=4 -> 2)
    parameter PW   = 8,             // payload width
    parameter DW   = 2*AW + PW      // total flit width
)(
    input  wire             clk,
    input  wire             rst_n,

    // ---------------- Local (PE) port ----------------
    input  wire             l_in_valid,
    input  wire [DW-1:0]    l_in_data,
    output wire             l_in_ready,
    output wire             l_out_valid,
    output wire [DW-1:0]    l_out_data,
    input  wire             l_out_ready,

    // ---------------- North port ----------------
    input  wire             n_in_valid,
    input  wire [DW-1:0]    n_in_data,
    output wire             n_in_ready,
    output wire             n_out_valid,
    output wire [DW-1:0]    n_out_data,
    input  wire             n_out_ready,

    // ---------------- South port ----------------
    input  wire             s_in_valid,
    input  wire [DW-1:0]    s_in_data,
    output wire             s_in_ready,
    output wire             s_out_valid,
    output wire [DW-1:0]    s_out_data,
    input  wire             s_out_ready,

    // ---------------- East port ----------------
    input  wire             e_in_valid,
    input  wire [DW-1:0]    e_in_data,
    output wire             e_in_ready,
    output wire             e_out_valid,
    output wire [DW-1:0]    e_out_data,
    input  wire             e_out_ready,

    // ---------------- West port ----------------
    input  wire             w_in_valid,
    input  wire [DW-1:0]    w_in_data,
    output wire             w_in_ready,
    output wire             w_out_valid,
    output wire [DW-1:0]    w_out_data,
    input  wire             w_out_ready
);

    localparam L = 0, N = 1, S = 2, E = 3, W = 4;

    // ---------------- external inputs, indexable ----------------
    wire [DW-1:0] ext_data  [0:4];
    wire          ext_valid [0:4];

    assign ext_data[L] = l_in_data;  assign ext_valid[L] = l_in_valid;
    assign ext_data[N] = n_in_data;  assign ext_valid[N] = n_in_valid;
    assign ext_data[S] = s_in_data;  assign ext_valid[S] = s_in_valid;
    assign ext_data[E] = e_in_data;  assign ext_valid[E] = e_in_valid;
    assign ext_data[W] = w_in_data;  assign ext_valid[W] = w_in_valid;

    // ---------------- per-input single-flit registers ----------------
    reg  [DW-1:0] data_reg  [0:4];
    reg           valid_reg [0:4];
    wire [4:0]    in_ready;   // pure state signal: ~valid_reg

    assign l_in_ready = in_ready[L];
    assign n_in_ready = in_ready[N];
    assign s_in_ready = in_ready[S];
    assign e_in_ready = in_ready[E];
    assign w_in_ready = in_ready[W];

    genvar gi;
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : READY
            assign in_ready[gi] = ~valid_reg[gi];
        end
    endgenerate

    // ---------------- XY routing computation (on the REGISTERED flit) ----------------
    wire [AW-1:0] dest_x [0:4];
    wire [AW-1:0] dest_y [0:4];
    reg  [2:0]    dest_port [0:4];   // holds L/N/S/E/W for each buffered input

    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : DECODE
            assign dest_x[gi] = data_reg[gi][DW-1     -: AW];
            assign dest_y[gi] = data_reg[gi][DW-AW-1   -: AW];
        end
    endgenerate

    integer k;
    always @(*) begin
        for (k = 0; k < 5; k = k + 1) begin
            if (dest_x[k] > XPOS)
                dest_port[k] = E;
            else if (dest_x[k] < XPOS)
                dest_port[k] = W;
            else if (dest_y[k] > YPOS)
                dest_port[k] = N;
            else if (dest_y[k] < YPOS)
                dest_port[k] = S;
            else
                dest_port[k] = L;
        end
    end

    // ---------------- request matrix: req_<OUT>[in_port] ----------------
    wire [4:0] req_L, req_N, req_S, req_E, req_W;
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : REQ
            assign req_L[gi] = valid_reg[gi] && (dest_port[gi] == L);
            assign req_N[gi] = valid_reg[gi] && (dest_port[gi] == N);
            assign req_S[gi] = valid_reg[gi] && (dest_port[gi] == S);
            assign req_E[gi] = valid_reg[gi] && (dest_port[gi] == E);
            assign req_W[gi] = valid_reg[gi] && (dest_port[gi] == W);
        end
    endgenerate

    // gate with downstream readiness (a neighbor's own state-based in_ready
    // signal) before arbitrating -- no combinational loop here since
    // out_ready is always some other router's pure-state signal.
    wire [4:0] gated_req_L = req_L & {5{l_out_ready}};
    wire [4:0] gated_req_N = req_N & {5{n_out_ready}};
    wire [4:0] gated_req_S = req_S & {5{s_out_ready}};
    wire [4:0] gated_req_E = req_E & {5{e_out_ready}};
    wire [4:0] gated_req_W = req_W & {5{w_out_ready}};

    wire [4:0] grant_L, grant_N, grant_S, grant_E, grant_W;

    rr_arbiter #(.N(5)) arb_L (.clk(clk), .rst_n(rst_n), .req(gated_req_L), .grant(grant_L));
    rr_arbiter #(.N(5)) arb_N (.clk(clk), .rst_n(rst_n), .req(gated_req_N), .grant(grant_N));
    rr_arbiter #(.N(5)) arb_S (.clk(clk), .rst_n(rst_n), .req(gated_req_S), .grant(grant_S));
    rr_arbiter #(.N(5)) arb_E (.clk(clk), .rst_n(rst_n), .req(gated_req_E), .grant(grant_E));
    rr_arbiter #(.N(5)) arb_W (.clk(clk), .rst_n(rst_n), .req(gated_req_W), .grant(grant_W));

    // ---------------- crossbar mux (one-hot select, from registered data) ----------------
    function [DW-1:0] mux5;
        input [4:0]    sel;
        input [DW-1:0] d0, d1, d2, d3, d4;
        begin
            mux5 = ({DW{sel[0]}} & d0) |
                   ({DW{sel[1]}} & d1) |
                   ({DW{sel[2]}} & d2) |
                   ({DW{sel[3]}} & d3) |
                   ({DW{sel[4]}} & d4);
        end
    endfunction

    assign l_out_data = mux5(grant_L, data_reg[0], data_reg[1], data_reg[2], data_reg[3], data_reg[4]);
    assign n_out_data = mux5(grant_N, data_reg[0], data_reg[1], data_reg[2], data_reg[3], data_reg[4]);
    assign s_out_data = mux5(grant_S, data_reg[0], data_reg[1], data_reg[2], data_reg[3], data_reg[4]);
    assign e_out_data = mux5(grant_E, data_reg[0], data_reg[1], data_reg[2], data_reg[3], data_reg[4]);
    assign w_out_data = mux5(grant_W, data_reg[0], data_reg[1], data_reg[2], data_reg[3], data_reg[4]);

    assign l_out_valid = |grant_L;
    assign n_out_valid = |grant_N;
    assign s_out_valid = |grant_S;
    assign e_out_valid = |grant_E;
    assign w_out_valid = |grant_W;

    // a buffered input is "consumed" this cycle if any output granted it
    wire [4:0] consumed;
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : CONSUMED
            assign consumed[gi] = grant_L[gi] | grant_N[gi] | grant_S[gi] | grant_E[gi] | grant_W[gi];
        end
    endgenerate

    // ---------------- sequential: input buffer load / drain ----------------
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 5; j = j + 1) begin
                valid_reg[j] <= 1'b0;
                data_reg[j]  <= {DW{1'b0}};
            end
        end else begin
            for (j = 0; j < 5; j = j + 1) begin
                if (consumed[j]) begin
                    // flit handed off downstream this cycle -> buffer empties
                    valid_reg[j] <= 1'b0;
                end else if (!valid_reg[j] && ext_valid[j]) begin
                    // buffer was empty and upstream is sending -> latch it
                    valid_reg[j] <= 1'b1;
                    data_reg[j]  <= ext_data[j];
                end
                // else: hold current state (occupied & waiting for grant)
            end
        end
    end

endmodule
