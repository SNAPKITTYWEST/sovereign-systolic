//============================================================================
// Testbench for systolic array + tensor core
//============================================================================

`timescale 1ns / 1ps

module tb_systolic_array;

    parameter int ROWS = 16;
    parameter int COLS = 16;

    logic clk, rst_n;
    logic start, done, busy;
    logic [3:0] opcode;
    logic [1:0] df_mode;

    logic [15:0] act_west  [ROWS];
    logic [15:0] wgt_north [COLS];
    logic [31:0] psum_south[COLS];

    initial clk = 0;
    always #5 clk = ~clk;

    systolic_array_16x16 #(
        .ROWS(ROWS), .COLS(COLS)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .opcode(opcode), .df_mode(df_mode),
        .busy(busy), .done(done),
        .act_west(act_west), .wgt_north(wgt_north),
        .psum_south(psum_south)
    );

    initial begin
        rst_n = 0;
        start = 0;
        opcode = 4'b0101; // MMA
        df_mode = 2'b00;  // WS

        for (int i = 0; i < ROWS; i++) act_west[i] = 16'h3C00;
        for (int j = 0; j < COLS; j++) wgt_north[j] = 16'h4000;

        #20 rst_n = 1;
        #20;

        $display("Starting systolic array...");
        start = 1;
        #10 start = 0;

        wait(done);
        $display("Done. psum_south[0] = %h", psum_south[0]);

        #50;
        $finish;
    end

endmodule
