// -----------------------------------------------------------------------
// tb_mesh_4x4_top.v
// Sends a handful of packets across the mesh and checks each one is
// received, unchanged, at the correct destination node's local port.
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module tb_mesh_4x4_top;

    localparam AW   = 2;
    localparam PW   = 8;
    localparam DW   = 2*AW + PW;
    localparam MESH = 4;
    localparam NN   = MESH*MESH;

    reg clk = 0;
    reg rst_n = 0;

    reg  [NN-1:0]     pe_in_valid;
    reg  [NN*DW-1:0]  pe_in_data;
    wire [NN-1:0]     pe_in_ready;

    wire [NN-1:0]     pe_out_valid;
    wire [NN*DW-1:0]  pe_out_data;
    reg  [NN-1:0]     pe_out_ready;

    integer errors = 0;
    integer received = 0;

    mesh_4x4_top #(.AW(AW), .PW(PW), .MESH(MESH)) dut (
        .clk(clk), .rst_n(rst_n),
        .pe_in_valid(pe_in_valid), .pe_in_data(pe_in_data), .pe_in_ready(pe_in_ready),
        .pe_out_valid(pe_out_valid), .pe_out_data(pe_out_data), .pe_out_ready(pe_out_ready)
    );

    always #5 clk = ~clk;   // 100 MHz

    function [AW-1:0] node_x; input integer id; begin node_x = id % MESH; end endfunction
    function [AW-1:0] node_y; input integer id; begin node_y = id / MESH; end endfunction

    function [DW-1:0] build_flit;
        input [AW-1:0] dx, dy;
        input [PW-1:0] payload;
        begin
            build_flit = {dx, dy, payload};
        end
    endfunction

    // send one flit from a source node's local input port
    task automatic send_flit;
        input integer src_id;
        input integer dst_id;
        input [PW-1:0] payload;
        begin
            pe_in_data[(src_id+1)*DW-1 -: DW] = build_flit(node_x(dst_id), node_y(dst_id), payload);
            pe_in_valid[src_id] = 1'b1;
            @(posedge clk);
            while (!pe_in_ready[src_id]) @(posedge clk);
            #1 pe_in_valid[src_id] = 1'b0;
        end
    endtask

    // watch a destination node's local output port and check the payload
    task automatic expect_flit;
        input integer dst_id;
        input [PW-1:0] exp_payload;
        integer timeout;
        begin
            timeout = 0;
            while (!(pe_out_valid[dst_id] && pe_out_ready[dst_id])) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 200) begin
                    $display("TIMEOUT waiting for node %0d", dst_id);
                    errors = errors + 1;
                    disable expect_flit;
                end
            end
            if (pe_out_data[dst_id*DW +: PW] !== exp_payload) begin
                $display("MISMATCH at node %0d: expected %0h got %0h",
                          dst_id, exp_payload, pe_out_data[dst_id*DW +: PW]);
                errors = errors + 1;
            end else begin
                $display("OK: node %0d received payload %0h", dst_id, exp_payload);
            end
            received = received + 1;
            @(posedge clk);
        end
    endtask

    initial begin
        pe_in_valid  = {NN{1'b0}};
        pe_in_data   = {(NN*DW){1'b0}};
        pe_out_ready = {NN{1'b1}};   // all local sinks always ready

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: corner to corner, (0,0) id=0 -> (3,3) id=15
        fork
            send_flit(0, 15, 8'hA1);
            expect_flit(15, 8'hA1);
        join

        // Test 2: pure X move, (1,0) id=1 -> (3,0) id=3
        fork
            send_flit(1, 3, 8'hB2);
            expect_flit(3, 8'hB2);
        join

        // Test 3: pure Y move, (2,0) id=2 -> (2,3) id=14
        fork
            send_flit(2, 14, 8'hC3);
            expect_flit(14, 8'hC3);
        join

        // Test 4: diagonal-ish turn, (3,3) id=15 -> (0,1) id=4
        fork
            send_flit(15, 4, 8'hD4);
            expect_flit(4, 8'hD4);
        join

        // Test 5: several packets in flight at once (different src/dst pairs)
        fork
            send_flit(0, 5, 8'hE5);
            send_flit(15, 10, 8'hF6);
            send_flit(3, 12, 8'h77);
        join
        fork
            expect_flit(5, 8'hE5);
            expect_flit(10, 8'hF6);
            expect_flit(12, 8'h77);
        join

        repeat (5) @(posedge clk);

        if (errors == 0)
            $display("\n*** ALL %0d PACKETS ROUTED CORRECTLY - TEST PASSED ***\n", received);
        else
            $display("\n*** %0d ERROR(S) OUT OF %0d PACKETS - TEST FAILED ***\n", errors, received);

        $finish;
    end

    initial begin
        $dumpfile("mesh_4x4.vcd");
        $dumpvars(0, tb_mesh_4x4_top);
    end

endmodule
