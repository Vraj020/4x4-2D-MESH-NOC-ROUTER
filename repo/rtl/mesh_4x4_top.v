// -----------------------------------------------------------------------
// mesh_4x4_top.v
// 4x4 2D mesh NoC built from 16 instances of noc_router (XY routing).
// Node id = y*4 + x  (x = column 0..3, y = row 0..3)
//
// PE-facing local ports are flattened vectors, one bit / DW-slice per node:
//   pe_in_valid[id], pe_in_data[(id+1)*DW-1 -: DW], pe_in_ready[id]
//   pe_out_valid[id], pe_out_data[(id+1)*DW-1 -: DW], pe_out_ready[id]
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module mesh_4x4_top #(
    parameter AW = 2,
    parameter PW = 8,
    parameter DW = 2*AW + PW,
    parameter MESH = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire [MESH*MESH-1:0]        pe_in_valid,
    input  wire [MESH*MESH*DW-1:0]     pe_in_data,
    output wire [MESH*MESH-1:0]        pe_in_ready,

    output wire [MESH*MESH-1:0]        pe_out_valid,
    output wire [MESH*MESH*DW-1:0]     pe_out_data,
    input  wire [MESH*MESH-1:0]        pe_out_ready
);

    // per-router output-side signals (driven by router x,y)
    wire [DW-1:0] N_out_d[0:MESH-1][0:MESH-1], S_out_d[0:MESH-1][0:MESH-1];
    wire [DW-1:0] E_out_d[0:MESH-1][0:MESH-1], W_out_d[0:MESH-1][0:MESH-1];
    wire          N_out_v[0:MESH-1][0:MESH-1], S_out_v[0:MESH-1][0:MESH-1];
    wire          E_out_v[0:MESH-1][0:MESH-1], W_out_v[0:MESH-1][0:MESH-1];
    wire          N_out_r[0:MESH-1][0:MESH-1], S_out_r[0:MESH-1][0:MESH-1];
    wire          E_out_r[0:MESH-1][0:MESH-1], W_out_r[0:MESH-1][0:MESH-1];

    // per-router input-side signals (consumed by router x,y)
    wire [DW-1:0] N_in_d[0:MESH-1][0:MESH-1], S_in_d[0:MESH-1][0:MESH-1];
    wire [DW-1:0] E_in_d[0:MESH-1][0:MESH-1], W_in_d[0:MESH-1][0:MESH-1];
    wire          N_in_v[0:MESH-1][0:MESH-1], S_in_v[0:MESH-1][0:MESH-1];
    wire          E_in_v[0:MESH-1][0:MESH-1], W_in_v[0:MESH-1][0:MESH-1];
    wire          N_in_r[0:MESH-1][0:MESH-1], S_in_r[0:MESH-1][0:MESH-1];
    wire          E_in_r[0:MESH-1][0:MESH-1], W_in_r[0:MESH-1][0:MESH-1];

    genvar x, y;

    // ---------------- instantiate the 16 routers ----------------
    generate
        for (y = 0; y < MESH; y = y + 1) begin : ROW
            for (x = 0; x < MESH; x = x + 1) begin : COL
                localparam integer ID = y*MESH + x;

                noc_router #(.XPOS(x), .YPOS(y), .AW(AW), .PW(PW), .DW(DW)) u_router (
                    .clk        (clk),
                    .rst_n      (rst_n),

                    .l_in_valid (pe_in_valid[ID]),
                    .l_in_data  (pe_in_data[(ID+1)*DW-1 -: DW]),
                    .l_in_ready (pe_in_ready[ID]),
                    .l_out_valid(pe_out_valid[ID]),
                    .l_out_data (pe_out_data[(ID+1)*DW-1 -: DW]),
                    .l_out_ready(pe_out_ready[ID]),

                    .n_in_valid (N_in_v[x][y]), .n_in_data(N_in_d[x][y]), .n_in_ready(N_in_r[x][y]),
                    .n_out_valid(N_out_v[x][y]),.n_out_data(N_out_d[x][y]),.n_out_ready(N_out_r[x][y]),

                    .s_in_valid (S_in_v[x][y]), .s_in_data(S_in_d[x][y]), .s_in_ready(S_in_r[x][y]),
                    .s_out_valid(S_out_v[x][y]),.s_out_data(S_out_d[x][y]),.s_out_ready(S_out_r[x][y]),

                    .e_in_valid (E_in_v[x][y]), .e_in_data(E_in_d[x][y]), .e_in_ready(E_in_r[x][y]),
                    .e_out_valid(E_out_v[x][y]),.e_out_data(E_out_d[x][y]),.e_out_ready(E_out_r[x][y]),

                    .w_in_valid (W_in_v[x][y]), .w_in_data(W_in_d[x][y]), .w_in_ready(W_in_r[x][y]),
                    .w_out_valid(W_out_v[x][y]),.w_out_data(W_out_d[x][y]),.w_out_ready(W_out_r[x][y])
                );
            end
        end
    endgenerate

    // ---------------- vertical links: (x,y) <-> (x,y+1) ----------------
    generate
        for (x = 0; x < MESH; x = x + 1) begin : VLINK_X
            for (y = 0; y < MESH-1; y = y + 1) begin : VLINK_Y
                // (x,y) north-out  -> (x,y+1) south-in
                assign S_in_d[x][y+1] = N_out_d[x][y];
                assign S_in_v[x][y+1] = N_out_v[x][y];
                assign N_out_r[x][y]  = S_in_r[x][y+1];

                // (x,y+1) south-out -> (x,y) north-in
                assign N_in_d[x][y] = S_out_d[x][y+1];
                assign N_in_v[x][y] = S_out_v[x][y+1];
                assign S_out_r[x][y+1] = N_in_r[x][y];
            end
            // boundary: top row has no north neighbor, bottom row no south neighbor
            assign N_in_v[x][MESH-1] = 1'b0;
            assign N_in_d[x][MESH-1] = {DW{1'b0}};
            assign N_out_r[x][MESH-1] = 1'b1;

            assign S_in_v[x][0] = 1'b0;
            assign S_in_d[x][0] = {DW{1'b0}};
            assign S_out_r[x][0] = 1'b1;
        end
    endgenerate

    // ---------------- horizontal links: (x,y) <-> (x+1,y) ----------------
    generate
        for (y = 0; y < MESH; y = y + 1) begin : HLINK_Y
            for (x = 0; x < MESH-1; x = x + 1) begin : HLINK_X
                // (x,y) east-out -> (x+1,y) west-in
                assign W_in_d[x+1][y] = E_out_d[x][y];
                assign W_in_v[x+1][y] = E_out_v[x][y];
                assign E_out_r[x][y]  = W_in_r[x+1][y];

                // (x+1,y) west-out -> (x,y) east-in
                assign E_in_d[x][y] = W_out_d[x+1][y];
                assign E_in_v[x][y] = W_out_v[x+1][y];
                assign W_out_r[x+1][y] = E_in_r[x][y];
            end
            // boundary: rightmost column has no east neighbor, leftmost no west neighbor
            assign E_in_v[MESH-1][y] = 1'b0;
            assign E_in_d[MESH-1][y] = {DW{1'b0}};
            assign E_out_r[MESH-1][y] = 1'b1;

            assign W_in_v[0][y] = 1'b0;
            assign W_in_d[0][y] = {DW{1'b0}};
            assign W_out_r[0][y] = 1'b1;
        end
    endgenerate

endmodule
