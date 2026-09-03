//============================================================================
// 16×16 Systolic Array Wrapper
// Supports WS / OS / IS dataflows + Tensor-Core mode
//============================================================================

`timescale 1ns / 1ps

module systolic_array_16x16 #(
    parameter int ROWS = 16,
    parameter int COLS = 16,
    parameter int DATA_W = 16,
    parameter int ACC_W  = 32,
    parameter int CTRL_W = 8
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [3:0]            opcode,
    input  dataflow_t             df_mode,
    output logic                  busy,
    output logic                  done,
    input  logic [DATA_W-1:0]     act_west  [ROWS],
    input  logic [DATA_W-1:0]     wgt_north [COLS],
    output logic [ACC_W-1:0]      psum_south[COLS]
);

    logic [CTRL_W-1:0] pe_ctrl;
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

    logic [DATA_W-1:0] act_h [ROWS][COLS+1];
    logic [DATA_W-1:0] wgt_v [ROWS+1][COLS];
    logic [ACC_W-1:0]  psum  [ROWS][COLS+1];

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r++) assign act_h[r][0] = act_west[r];
        for (c = 0; c < COLS; c++) assign wgt_v[0][c] = wgt_north[c];
    endgenerate

    generate
        for (r = 0; r < ROWS; r++) begin : gen_row
            for (c = 0; c < COLS; c++) begin : gen_col
                systolic_pe #(
                    .DATA_W(DATA_W), .ACC_W(ACC_W), .CTRL_W(CTRL_W)
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

endmodule
