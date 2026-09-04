module ember_cpu #(
    parameter logic [15:0] TOKEN_LIMIT = 16'd8192
) (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction memory
    output logic [15:0] imem_addr,
    input  logic [15:0] imem_rdata,

    // Data memory
    output logic [15:0] dmem_addr,
    output logic [15:0] dmem_wdata,
    input  logic [15:0] dmem_rdata,
    output logic        dmem_re,
    output logic        dmem_we,

    // Architectural status
    output logic        halted,
    output logic        token_limit_hit,
    output logic [15:0] token_count
);

    // ============================================================
    // EMBER 16-bit ISA
    //
    // 16-bit instruction
    //
    // [15:12] opcode
    // [11:9]  rd
    // [8:6]   rs1
    // [5:3]   rs2
    // [2:0]   function / sub-op
    //
    // Immediate forms use [5:0]
    // Branch forms use [11:0]
    //
    // Register x0 is permanently zero.
    // ============================================================

    localparam logic [3:0] OP_RTYPE = 4'h0;
    localparam logic [3:0] OP_ADDI  = 4'h1;
    localparam logic [3:0] OP_ANDI  = 4'h2;
    localparam logic [3:0] OP_ORI   = 4'h3;
    localparam logic [3:0] OP_XORI  = 4'h4;
    localparam logic [3:0] OP_LW    = 4'h5;
    localparam logic [3:0] OP_BEQ   = 4'h6;
    localparam logic [3:0] OP_BNE   = 4'h7;
    localparam logic [3:0] OP_BLT   = 4'h8;
    localparam logic [3:0] OP_BGE   = 4'h9;
    localparam logic [3:0] OP_SW    = 4'hA;
    localparam logic [3:0] OP_LUI   = 4'hB;
    localparam logic [3:0] OP_JMP   = 4'hC;
    localparam logic [3:0] OP_JAL   = 4'hD;
    localparam logic [3:0] OP_HALT  = 4'hE;
    localparam logic [3:0] OP_NOP   = 4'hF;

    // ============================================================
    // R-type functions
    // ============================================================

    localparam logic [2:0] FN_ADD = 3'b000;
    localparam logic [2:0] FN_SUB = 3'b001;
    localparam logic [2:0] FN_AND = 3'b010;
    localparam logic [2:0] FN_OR  = 3'b011;
    localparam logic [2:0] FN_XOR = 3'b100;
    localparam logic [2:0] FN_SLL = 3'b101;
    localparam logic [2:0] FN_SRL = 3'b110;
    localparam logic [2:0] FN_SRA = 3'b111;

    // ============================================================
    // Processor phases
    // ============================================================

    typedef enum logic [2:0] {
        PH_FETCH    = 3'd0,
        PH_DECODE   = 3'd1,
        PH_EXECUTE  = 3'd2,
        PH_MEMORY   = 3'd3,
        PH_WRITEBACK = 3'd4
    } phase_t;

    phase_t phase;

    // ============================================================
    // Architectural state
    // ============================================================

    logic [15:0] pc;
    logic [15:0] ir;

    logic [15:0] regfile [0:7];

    logic z_flag;
    logic n_flag;
    logic c_flag;
    logic v_flag;

    // ============================================================
    // Decode registers
    // ============================================================

    logic [3:0] dec_opcode;
    logic [2:0] dec_rd;
    logic [2:0] dec_rs1;
    logic [2:0] dec_rs2;
    logic [2:0] dec_func;

    logic [5:0] dec_imm6_raw;
    logic [11:0] dec_imm12_raw;

    logic [15:0] dec_imm6_sext;
    logic [15:0] dec_imm6_zext;
    logic [15:0] dec_imm12_sext;

    logic [15:0] dec_pc_plus1;

    logic [15:0] dec_rs1_data;
    logic [15:0] dec_rs2_data;

    // ============================================================
    // Execute state
    // ============================================================

    logic [15:0] alu_a;
    logic [15:0] alu_b;
    logic [15:0] alu_result;

    logic alu_z;
    logic alu_n;
    logic alu_c;
    logic alu_v;

    logic branch_taken;
    logic [15:0] branch_target;

    // ============================================================
    // Memory / writeback state
    // ============================================================

    logic [15:0] mem_result;
    logic [15:0] wb_result;

    logic        wb_enable;
    logic [2:0]  wb_rd;

    logic        mem_pending;
    logic        mem_is_load;
    logic        mem_is_store;

    // ============================================================
    // Token accounting
    //
    // A token is represented architecturally by a retired
    // instruction. The counter is hardware state, not a model
    // assertion.
    // ============================================================

    logic token_retire;

    assign token_limit_hit = (token_count >= TOKEN_LIMIT);

    // Saturating token counter.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_count <= 16'd0;
        end
        else if (token_retire && !token_limit_hit) begin
            if (token_count == TOKEN_LIMIT - 16'd1)
                token_count <= TOKEN_LIMIT;
            else
                token_count <= token_count + 16'd1;
        end
    end

    // ============================================================
    // Register reads
    // ============================================================

    always_comb begin
        if (dec_rs1 == 3'd0)
            dec_rs1_data = 16'd0;
        else
            dec_rs1_data = regfile[dec_rs1];

        if (dec_rs2 == 3'd0)
            dec_rs2_data = 16'd0;
        else
            dec_rs2_data = regfile[dec_rs2];
    end

    // ============================================================
    // Immediate generation
    // ============================================================

    always_comb begin
        dec_imm6_raw   = ir[5:0];
        dec_imm12_raw  = ir[11:0];

        dec_imm6_sext  = {{10{ir[5]}}, ir[5:0]};
        dec_imm6_zext  = {10'd0, ir[5:0]};
        dec_imm12_sext = {{4{ir[11]}}, ir[11:0]};
    end

    // ============================================================
    // Instruction decode
    // ============================================================

    always_comb begin
        dec_opcode = ir[15:12];
        dec_rd     = ir[11:9];
        dec_rs1    = ir[8:6];
        dec_rs2    = ir[5:3];
        dec_func   = ir[2:0];

        dec_pc_plus1 = pc + 16'd1;
    end

    // ============================================================
    // ALU
    // ============================================================

    always_comb begin
        alu_a = dec_rs1_data;
        alu_b = dec_rs2_data;

        case (dec_opcode)

            OP_RTYPE: begin
                alu_a = dec_rs1_data;
                alu_b = dec_rs2_data;
            end

            OP_ADDI: begin
                alu_a = dec_rs1_data;
                alu_b = dec_imm6_sext;
            end

            OP_ANDI: begin
                alu_a = dec_rs1_data;
                alu_b = dec_imm6_zext;
            end

            OP_ORI: begin
                alu_a = dec_rs1_data;
                alu_b = dec_imm6_zext;
            end

            OP_XORI: begin
                alu_a = dec_rs1_data;
                alu_b = dec_imm6_zext;
            end

            OP_LW: begin
                alu_a = dec_rs1_data;
                alu_b = dec_imm6_sext;
            end

            OP_SW: begin
                alu_a = dec_rs1_data;
                alu_b = dec_imm6_sext;
            end

            OP_BEQ,
            OP_BNE,
            OP_BLT,
            OP_BGE: begin
                alu_a = dec_rs1_data;
                alu_b = dec_rs2_data;
            end

            default: begin
                alu_a = dec_rs1_data;
                alu_b = dec_rs2_data;
            end

        endcase
    end

    // ============================================================
    // ALU operation and flags
    // ============================================================

    always_comb begin
        alu_result = 16'd0;

        alu_z = 1'b0;
        alu_n = 1'b0;
        alu_c = 1'b0;
        alu_v = 1'b0;

        case (dec_opcode)

            OP_RTYPE: begin

                case (dec_func)

                    FN_ADD: begin
                        {alu_c, alu_result} = alu_a + alu_b;

                        alu_v =
                            (~(alu_a[15] ^ alu_b[15])) &
                            (alu_result[15] ^ alu_a[15]);
                    end

                    FN_SUB: begin
                        {alu_c, alu_result} = alu_a - alu_b;

                        alu_v =
                            (alu_a[15] ^ alu_b[15]) &
                            (alu_result[15] ^ alu_a[15]);
                    end

                    FN_AND: begin
                        alu_result = alu_a & alu_b;
                    end

                    FN_OR: begin
                        alu_result = alu_a | alu_b;
                    end

                    FN_XOR: begin
                        alu_result = alu_a ^ alu_b;
                    end

                    FN_SLL: begin
                        alu_result = alu_a << alu_b[3:0];
                    end

                    FN_SRL: begin
                        alu_result = alu_a >> alu_b[3:0];
                    end

                    FN_SRA: begin
                        alu_result = $signed(alu_a) >>> alu_b[3:0];
                    end

                    default: begin
                        alu_result = 16'd0;
                    end

                endcase
            end

            OP_ADDI: begin
                {alu_c, alu_result} = alu_a + alu_b;

                alu_v =
                    (~(alu_a[15] ^ alu_b[15])) &
                    (alu_result[15] ^ alu_a[15]);
            end

            OP_ANDI: begin
                alu_result = alu_a & alu_b;
            end

            OP_ORI: begin
                alu_result = alu_a | alu_b;
            end

            OP_XORI: begin
                alu_result = alu_a ^ alu_b;
            end

            OP_LW,
            OP_SW: begin
                {alu_c, alu_result} = alu_a + alu_b;
            end

            OP_BEQ,
            OP_BNE,
            OP_BLT,
            OP_BGE: begin
                {alu_c, alu_result} = alu_a - alu_b;

                alu_v =
                    (alu_a[15] ^ alu_b[15]) &
                    (alu_result[15] ^ alu_a[15]);
            end

            default: begin
                alu_result = 16'd0;
            end

        endcase

        alu_z = (alu_result == 16'd0);
        alu_n = alu_result[15];
    end

    // ============================================================
    // Branch logic
    // ============================================================

    always_comb begin

        branch_taken = 1'b0;

        case (dec_opcode)

            OP_BEQ: begin
                branch_taken = (dec_rs1_data == dec_rs2_data);
            end

            OP_BNE: begin
                branch_taken = (dec_rs1_data != dec_rs2_data);
            end

            OP_BLT: begin
                branch_taken = ($signed(dec_rs1_data) <
                                 $signed(dec_rs2_data));
            end

            OP_BGE: begin
                branch_taken = ($signed(dec_rs1_data) >=
                                 $signed(dec_rs2_data));
            end

            default: begin
                branch_taken = 1'b0;
            end

        endcase

        branch_target = dec_pc_plus1 + dec_imm12_sext;
    end

    // ============================================================
    // Memory interface
    // ============================================================

    always_comb begin

        dmem_addr  = alu_result;
        dmem_wdata = dec_rs2_data;

        dmem_re = 1'b0;
        dmem_we = 1'b0;

        if (phase == PH_MEMORY) begin

            if (dec_opcode == OP_LW) begin
                dmem_re = 1'b1;
            end

            if (dec_opcode == OP_SW) begin
                dmem_we = 1'b1;
            end

        end
    end

    // ============================================================
    // Instruction memory address
    // ============================================================

    assign imem_addr = pc;

    // ============================================================
    // Writeback selection
    // ============================================================

    always_comb begin

        wb_enable = 1'b0;
        wb_rd     = dec_rd;
        wb_result  = alu_result;

        case (dec_opcode)

            OP_RTYPE,
            OP_ADDI,
            OP_ANDI,
            OP_ORI,
            OP_XORI: begin
                wb_enable = 1'b1;
                wb_result = alu_result;
            end

            OP_LW: begin
                wb_enable = 1'b1;
                wb_result = dmem_rdata;
            end

            OP_LUI: begin
                wb_enable = 1'b1;
                wb_result = {dec_imm6_raw, 10'd0};
            end

            OP_JAL: begin
                wb_enable = 1'b1;
                wb_result = dec_pc_plus1;
            end

            default: begin
                wb_enable = 1'b0;
                wb_result = alu_result;
            end

        endcase
    end

    // ============================================================
    // Token retirement
    //
    // One instruction retires during WRITEBACK.
    // HALT also retires as an architectural event.
    //
    // If the token limit has already been reached, no additional
    // instruction can retire.
    // ============================================================

    always_comb begin

        token_retire = 1'b0;

        if (phase == PH_WRITEBACK &&
            !halted &&
            !token_limit_hit) begin

            token_retire = 1'b1;

        end

    end

    // ============================================================
    // Main sequential machine
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            phase  <= PH_FETCH;
            pc     <= 16'd0;
            ir     <= 16'd0;

            z_flag <= 1'b0;
            n_flag <= 1'b0;
            c_flag <= 1'b0;
            v_flag <= 1'b0;

            mem_result  <= 16'd0;
            mem_pending <= 1'b0;
            mem_is_load <= 1'b0;
            mem_is_store <= 1'b0;

            halted <= 1'b0;

            for (integer i = 0; i < 8; i = i + 1)
                regfile[i] <= 16'd0;

        end
        else begin

            // x0 is always zero.
            regfile[0] <= 16'd0;

            // Hardware token limit has priority.
            if (token_limit_hit) begin
                halted <= 1'b1;
                phase  <= PH_FETCH;
            end

            else begin

                case (phase)

                    // ------------------------------------------------
                    // FETCH
                    // ------------------------------------------------

                    PH_FETCH: begin

                        ir <= imem_rdata;

                        phase <= PH_DECODE;

                    end

                    // ------------------------------------------------
                    // DECODE
                    // ------------------------------------------------

                    PH_DECODE: begin

                        phase <= PH_EXECUTE;

                    end

                    // ------------------------------------------------
                    // EXECUTE
                    // ------------------------------------------------

                    PH_EXECUTE: begin

                        case (dec_opcode)

                            OP_BEQ,
                            OP_BNE,
                            OP_BLT,
                            OP_BGE: begin

                                if (branch_taken)
                                    pc <= branch_target;
                                else
                                    pc <= dec_pc_plus1;

                            end

                            OP_JMP: begin

                                pc <= dec_pc_plus1 +
                                      dec_imm12_sext;

                            end

                            OP_JAL: begin

                                pc <= dec_pc_plus1 +
                                      dec_imm12_sext;

                            end

                            default: begin
                                pc <= dec_pc_plus1;
                            end

                        endcase

                        alu_result <= alu_result;

                        z_flag <= alu_z;
                        n_flag <= alu_n;
                        c_flag <= alu_c;
                        v_flag <= alu_v;

                        case (dec_opcode)

                            OP_LW,
                            OP_SW: begin
                                phase <= PH_MEMORY;
                            end

                            OP_HALT: begin
                                phase <= PH_WRITEBACK;
                            end

                            default: begin
                                phase <= PH_WRITEBACK;
                            end

                        endcase

                    end

                    // ------------------------------------------------
                    // MEMORY
                    // ------------------------------------------------

                    PH_MEMORY: begin

                        if (dec_opcode == OP_LW) begin

                            mem_result <= dmem_rdata;
                            mem_pending <= 1'b1;
                            mem_is_load <= 1'b1;

                        end

                        else if (dec_opcode == OP_SW) begin

                            mem_pending <= 1'b0;
                            mem_is_store <= 1'b1;

                        end

                        phase <= PH_WRITEBACK;

                    end

                    // ------------------------------------------------
                    // WRITEBACK / RETIRE
                    // ------------------------------------------------

                    PH_WRITEBACK: begin

                        // HALT is an architectural terminal state.
                        if (dec_opcode == OP_HALT) begin

                            halted <= 1'b1;
                        end

                        else begin

                            if (wb_enable &&
                                wb_rd != 3'd0) begin

                                regfile[wb_rd] <= wb_result;

                            end

                        end

                        mem_pending <= 1'b0;
                        mem_is_load <= 1'b0;
                        mem_is_store <= 1'b0;

                        if (!token_limit_hit)
                            phase <= PH_FETCH;
                        else
                            halted <= 1'b1;

                    end

                    default: begin

                        phase <= PH_FETCH;

                    end

                endcase

            end

        end

    end

endmodule
