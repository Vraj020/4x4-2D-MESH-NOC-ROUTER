// -----------------------------------------------------------------------
// rr_arbiter.v
// Generic N-input round-robin arbiter.
// One-hot "grant" output. Pointer rotates to just after the granted
// requester so every requester eventually gets served (starvation-free).
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module rr_arbiter #(
    parameter N = 5
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [N-1:0]  req,
    output reg  [N-1:0]  grant
);

    integer i, idx;
    reg found;
    reg [2:0] ptr;  // current highest-priority requester index (0..N-1)

    // combinational priority scan starting from ptr, wrapping around
    always @(*) begin
        grant = {N{1'b0}};
        found = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            idx = (ptr + i) % N;
            if (!found && req[idx]) begin
                grant[idx] = 1'b1;
                found      = 1'b1;
            end
        end
    end

    // pointer update: move priority to just after whoever was granted
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= 3'd0;
        end else if (|grant) begin
            for (i = 0; i < N; i = i + 1)
                if (grant[i]) ptr <= (i + 1) % N;
        end
    end

endmodule
