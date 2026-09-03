//============================================================================
// Integration: Tensor Core mode inside the 16×16 systolic array
//============================================================================

`timescale 1ns / 1ps

module systolic_array_with_tensor_core #(
    parameter int ROWS = 16,
    parameter int COLS = 16
)(
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    input  logic [3:0]    opcode,
    input  dataflow_t     df_mode,
    output logic          busy,
    output logic          done,

    input  logic [15:0]   act_west  [ROWS],
    input  logic [15:0]   wgt_north [COLS],
    output logic [31:0]   psum_south[COLS]
);

    logic [7:0] pe_ctrl;
    logic feeder_en, collector_en, barrier;
    dataflow_t df_int;

    array_controller u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .start(start), .opcode(opcode), .opcode_valid(1'b1),
        .df_mode(df_mode),
        .busy(busy), .done(done),
        .pe_ctrl(pe_ctrl),
        .feeder_en(feeder_en), .collector_en(collector_en),
        .barrier(barrier), .df_mode_out(df_int)
    );

    logic [15:0] act_h [ROWS][COLS+1];
    logic [15:0] wgt_v [ROWS+1][COLS];
    logic [31:0] psum  [ROWS][COLS+1];

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r++) assign act_h[r][0] = act_west[r];
        for (c = 0; c < COLS; c++) assign wgt_v[0][c] = wgt_north[c];
    endgenerate

    generate
        for (r = 0; r < ROWS; r++) begin : gen_row
            for (c = 0; c < COLS; c++) begin : gen_col
                systolic_pe #(
                    .DATA_W(16), .ACC_W(32), .CTRL_W(8)
                ) u_pe (
                    .clk(clk), .rst_n(rst_n),
                    .act_in(act_h[r][c]),
                    .wgt_in(wgt_v[r][c]),
                    .psum_in(c == 0 ? '0 : psum[r][c]),
                    .ctrl(pe_ctrl),
                    .df_mode(df_int),
                    .act_out(act_h[r][c+1]),
                    .wgt_out(wgt_v[r+1][c]),
                    .psum_out(psum[r][c+1]),
                    .busy()
                );
            end
        end
    endgenerate

    generate
        for (c = 0; c < COLS; c++)
            assign psum_south[c] = psum[ROWS-1][c+1];
    endgenerate

    //---------------------------------------------------------------
    // Tensor-Core mode overlay
    //---------------------------------------------------------------
    logic tc_start, tc_done, tc_busy;
    logic [15:0] tc_a [16][16];
    logic [15:0] tc_b [16][8];
    logic [31:0] tc_c_in  [16][8];
    logic [31:0] tc_c_out [16][8];

    tensor_core_fp16 #(.M(16), .N(8), .K(16)) u_tensor_core (
        .clk(clk), .rst_n(rst_n),
        .start(tc_start), .done(tc_done), .busy(tc_busy),
        .a_matrix(tc_a), .b_matrix(tc_b),
        .c_in(tc_c_in), .c_out(tc_c_out)
    );

endmodule
