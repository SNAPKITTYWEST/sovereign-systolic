//============================================================================
// Array Controller (Microcode-driven)
// Decodes 4-bit Tensor ISA opcodes, drives PE control signals
//============================================================================

`timescale 1ns / 1ps

module array_controller #(
    parameter int CTRL_W    = 8,
    parameter int ROM_DEPTH = 512,
    parameter int ADDR_W    = 9
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    input  logic [3:0]            opcode,
    input  logic                  opcode_valid,
    input  dataflow_t             df_mode,
    output logic                  busy,
    output logic                  done,
    output logic [CTRL_W-1:0]     pe_ctrl,
    output logic                  feeder_en,
    output logic                  collector_en,
    output logic                  barrier,
    output dataflow_t             df_mode_out
);

    logic [31:0] rom [0:ROM_DEPTH-1];
    logic [ADDR_W-1:0] pc;
    logic [31:0] curr;

    initial begin
        for (int i = 0; i < ROM_DEPTH; i++) rom[i] = 32'h0;
        rom[0]  = 32'h1000_0001;
        rom[1]  = 32'h1100_0001;
        rom[2]  = 32'h1010_0001;
        rom[3]  = 32'h0010_0001;
    end

    typedef enum logic [2:0] {IDLE, FETCH, EXEC, BARRIER, DONE_ST} state_t;
    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pc <= '0;
            busy <= 0;
            done <= 0;
            pe_ctrl <= '0;
            feeder_en <= 0;
            collector_en <= 0;
            barrier <= 0;
            df_mode_out <= DF_WEIGHT_STATIONARY;
        end else begin
            done <= 0;
            unique case (state)
                IDLE: if (start && opcode_valid) begin
                    pc <= {5'b0, opcode};
                    df_mode_out <= df_mode;
                    busy <= 1;
                    state <= FETCH;
                end
                FETCH: begin
                    curr <= rom[pc];
                    state <= EXEC;
                end
                EXEC: begin
                    pe_ctrl      <= curr[7:0];
                    feeder_en    <= curr[8];
                    collector_en <= curr[9];
                    barrier      <= curr[10];
                    pc <= pc + 1;
                    state <= barrier ? BARRIER : (curr == 0 ? DONE_ST : FETCH);
                end
                BARRIER: state <= FETCH;
                DONE_ST: begin
                    done <= 1;
                    busy <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
