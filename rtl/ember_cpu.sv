module ember_cpu (
    input  logic        clk,
    input  logic        rst_n,          // Active-low asynchronous reset

    // Instruction memory interface
    output logic [15:0] imem_addr,
    input  logic [15:0] imem_rdata,

    // Data memory interface
    output logic [15:0] dmem_addr,
    output logic [15:0] dmem_wdata,
    input  logic [15:0] dmem_rdata,
    output logic        dmem_re,
    output logic        dmem_we,

    // Status
    output logic        halted
);

    // ========================================================================
    // State Machine
    // ========================================================================
    typedef enum logic [2:0] {
        PH_FETCH    = 3'd0,
        PH_DECODE   = 3'd1,
        PH_EXECUTE  = 3'd2,
        PH_MEMORY   = 3'd3,
        PH_WRITEBACK= 3'd4
    } phase_t;

    phase_t phase, phase_next;

    // ========================================================================
    // Architectural State
    // ========================================================================
    logic [15:0] pc, pc_next;
    logic [15:0] regfile [0:7];
    logic [15:0] ir;                    // Instruction register
    logic        flag_z, flag_n, flag_c, flag_v;
    logic        halt_reg;

    // ========================================================================
    // Instruction Decode (combinatorial)
    // ========================================================================
    logic [3:0]  opcode;
    logic [2:0]  rd_addr, rs1_addr, rs2_addr, func;
    logic [5:0]  imm6;
    logic [11:0] imm12;
    logic [15:0] imm6_sext, imm6_zext, imm12_sext;

    always_comb begin
        opcode   = ir[15:12];
        rd_addr  = ir[11:9];
        rs1_addr = ir[8:6];
        rs2_addr = ir[5:3];
        func     = ir[2:0];
        imm6     = ir[5:0];
        imm12    = ir[11:0];

        imm6_sext  = {{10{imm6[5]}}, imm6};
        imm6_zext  = {10'b0, imm6};
        imm12_sext = {{4{imm12[11]}}, imm12};
    end

    // ========================================================================
    // Register File Read (combinatorial)
    // ========================================================================
    logic [15:0] rs1_data, rs2_data, rd_data;

    always_comb begin
        rs1_data = (rs1_addr == 3'd0) ? 16'd0 : regfile[rs1_addr];
        rs2_data = (rs2_addr == 3'd0) ? 16'd0 : regfile[rs2_addr];
        rd_data  = (rd_addr  == 3'd0) ? 16'd0 : regfile[rd_addr];
    end

    // ========================================================================
    // Pipeline Registers (latched at decode)
    // ========================================================================
    logic [15:0] dec_rs1, dec_rs2, dec_rd, dec_imm;
    logic [15:0] dec_pc_plus1;
    logic [3:0]  dec_opcode;
    logic [2:0]  dec_rd_addr, dec_func;
    logic [15:0] dec_imm12_sext;
    logic [5:0]  dec_imm6_raw;

    // ========================================================================
    // ALU
    // ========================================================================
    logic [2:0]  alu_op_sel;
    logic [15:0] alu_a, alu_b, alu_result;
    logic [16:0] alu_add_tmp;
    logic        alu_z, alu_n, alu_c, alu_v;

    // ALU operation mux based on opcode and func
    always_comb begin
        // Default ALU operands
        alu_a = dec_rs1;

        // ALU B operand selection
        case (dec_opcode)
            4'h0:    alu_b = dec_rs2;                                      // R-type: register
            4'h2, 4'h3, 4'hB: alu_b = {10'b0, dec_imm6_raw};            // ANDI/ORI/XORI: zero-extended
            4'h6, 4'h7, 4'h8: alu_b = dec_rs1;                           // Branch: compare rd vs rs1
            default: alu_b = dec_imm;                                      // Sign-extended immediate
        endcase

        // For branches, alu_a is rd_data
        if (dec_opcode == 4'h6 || dec_opcode == 4'h7 || dec_opcode == 4'h8) begin
            alu_a = dec_rd;
            alu_b = dec_rs1;
        end

        // ALU operation select
        case (dec_opcode)
            4'h0:    alu_op_sel = dec_func;     // R-type uses func field
            4'h1:    alu_op_sel = 3'd0;         // ADDI → ADD
            4'h2:    alu_op_sel = 3'd2;         // ANDI → AND
            4'h3:    alu_op_sel = 3'd3;         // ORI  → OR
            4'h4:    alu_op_sel = 3'd0;         // LW   → ADD (addr calc)
            4'h5:    alu_op_sel = 3'd0;         // SW   → ADD (addr calc)
            4'h