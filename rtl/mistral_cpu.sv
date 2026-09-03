module cpu (
    input wire clk,
    input wire reset,
    // Memory interfaces
    output wire [7:0] instr_addr,
    input wire [7:0] instr_data,
    output wire [7:0] data_addr,
    output wire [7:0] data_wdata,
    input wire [7:0] data_rdata,
    output wire data_we
);

    // Registers
    reg [7:0] reg_file [0:7];
    reg [7:0] pc, ir;
    reg [1:0] microstate;
    reg [15:0] microcode_rom [0:15];

    // Control signals
    reg [1:0] alu_op;
    reg reg_write, mem_read, mem_write, pc_inc, pc_load, ir_load;
    reg src_sel, dst_sel;
    reg [3:0] imm_src;

    // Internal wires
    wire [7:0] alu_out;
    wire [7:0] src_data = src_sel ? {4'b0, imm_src} : reg_file[ir[3:0]];
    wire [7:0] dst_data = dst_sel ? pc : reg_file[ir[7:4]];

    // ALU
    always_comb begin
        case (alu_op)
            2'b00: alu_out = reg_file[ir[7:4]] + src_data;
            2'b01: alu_out = reg_file[ir[7:4]] - src_data;
            2'b10: alu_out = reg_file[ir[7:4]] & src_data;
            2'b11: alu_out = reg_file[ir[7:4]] | src_data;
        endcase
    end

    // Microcode ROM initialization
    initial begin
        microcode_rom[0]  = 16'b0000000000000001;  // Fetch
        microcode_rom[1]  = 16'b0000001000000000;  // ADD
        microcode_rom[2]  = 16'b0000010001000000;  // SUB
        microcode_rom[3]  = 16'b0000011010000000;  // AND
        microcode_rom[4]  = 16'b0000100011000000;  // OR
        microcode_rom[5]  = 16'b0000101000010000;  // LDI
        microcode_rom[6]  = 16'b0000110000100000;  // LDR
        microcode_rom[7]  = 16'b0000111001000000;  // STR
        microcode_rom[8]  = 16'b0001000000000000;  // BRZ (conditional)
        // Remaining entries unused
        for (int i = 9; i < 16; i++) microcode_rom[i] = 16'b0;
    end

    // Microcode sequencer
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 8'b0;
            microstate <= 2'b00;
        end else begin
            case (microstate)
                2'b00: begin  // Fetch
                    ir <= instr_data;
                    pc <= pc + 1;
                    microstate <= 2'b01;
                end
                2'b01: begin  // Execute
                    {alu_op, reg_write, mem_read, mem_write, pc_inc, pc_load, ir_load, src_sel, dst_sel, imm_src} <= microcode_rom[ir[7:4]];
                    if (reg_write) reg_file[ir[7:4]] <= alu_out;
                    if (mem_read) reg_file[ir[7:4]] <= data_rdata;
                    if (mem_write) data_we <= 1;
                    if (pc_load && (reg_file[ir[3:0]] == 0)) pc <= pc + {4'b0, ir[3:0]};
                    microstate <= 2'b00;
                end
            endcase
        end
    end

    // Memory interfaces
    assign instr_addr = pc;
    assign data_addr = reg_file[ir[3:0]];
    assign data_wdata = reg_file[ir[7:4]];

endmodule