//============================================================================
// Systolic Array Processing Element (PE)
// Supports Weight-Stationary, Output-Stationary, Input-Stationary modes
// Designed for the 4-bit Tensor Microcode ISA
//============================================================================

`timescale 1ns / 1ps

module systolic_pe #(
    parameter int DATA_W = 16,
    parameter int ACC_W  = 32,
    parameter int CTRL_W = 8
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [DATA_W-1:0]     act_in,
    input  logic [DATA_W-1:0]     wgt_in,
    input  logic [ACC_W-1:0]      psum_in,
    input  logic [CTRL_W-1:0]     ctrl,
    input  dataflow_t             df_mode,
    output logic [DATA_W-1:0]     act_out,
    output logic [DATA_W-1:0]     wgt_out,
    output logic [ACC_W-1:0]      psum_out,
    output logic                  busy
);

    logic load_wgt_reg, load_act_reg, acc_en, psum_sel;
    logic sparse_en, pass_through, clear_acc, output_en;

    assign {load_wgt_reg, load_act_reg, acc_en, psum_sel,
            sparse_en, pass_through, clear_acc, output_en} = ctrl;

    logic [DATA_W-1:0] wgt_reg, act_reg;
    logic [ACC_W-1:0]  acc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_reg <= '0;
            act_reg <= '0;
        end else begin
            unique case (df_mode)
                DF_WEIGHT_STATIONARY: if (load_wgt_reg) wgt_reg <= wgt_in;
                DF_INPUT_STATIONARY : if (load_act_reg) act_reg <= act_in;
                default: ;
            endcase
        end
    end

    logic [DATA_W-1:0] mul_a, mul_b;
    always_comb begin
        unique case (df_mode)
            DF_WEIGHT_STATIONARY: begin mul_a = act_in;  mul_b = wgt_reg; end
            DF_INPUT_STATIONARY:  begin mul_a = act_reg; mul_b = wgt_in;  end
            DF_OUTPUT_STATIONARY, DF_TENSOR_CORE: begin mul_a = act_in; mul_b = wgt_in; end
            default: begin mul_a = act_in; mul_b = wgt_in; end
        endcase
    end

    logic signed [2*DATA_W-1:0] product = $signed(mul_a) * $signed(mul_b);
    logic [ACC_W-1:0] product_ext = {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};
    logic [ACC_W-1:0] gated_product = (sparse_en && !sparse_mask[0]) ? '0 : product_ext;
    logic [ACC_W-1:0] add_b = (df_mode == DF_OUTPUT_STATIONARY || psum_sel) ? acc : psum_in;
    logic [ACC_W-1:0] sum = gated_product + add_b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          acc <= '0;
        else if (clear_acc)  acc <= '0;
        else if (acc_en)     acc <= sum;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_out  <= '0;
            wgt_out  <= '0;
            psum_out <= '0;
        end else if (pass_through) begin
            act_out  <= act_in;
            wgt_out  <= wgt_in;
            psum_out <= psum_in;
        end else begin
            act_out  <= act_in;
            wgt_out  <= wgt_in;
            psum_out <= output_en ? sum : psum_in;
        end
    end

    assign busy = acc_en | load_wgt_reg | load_act_reg;

endmodule
