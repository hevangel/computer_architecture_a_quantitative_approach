module multicycle_microcode_baseline #(parameter bit MICROCODE=0)(
    input logic clk, rst_n,
    output wire [31:0] imem_addr,
    input logic [31:0] imem_rdata,
    output wire [31:0] dmem_addr, dmem_wdata,
    output wire dmem_we,
    input logic [31:0] dmem_rdata,
    input logic [4:0] dbg_raddr,
    output wire [31:0] dbg_rdata,
    output logic halted,
    output logic [31:0] cycles, retired
);
    import rv32i_pkg::*;
    localparam integer FETCH=0, DECODE=1, EXECUTE=2, MEMORY=3, FINISH=4;
    logic [2:0] fsm_state, micro_pc, next_fsm, next_micro;
    logic [4:0] control;
    logic [31:0] regs [0:31];
    logic [31:0] pc, instruction, operand_a, operand_b, value, next_pc;
    wire [6:0] op=instruction[6:0];
    wire [2:0] fn=instruction[14:12];
    wire [31:0] i_imm={{20{instruction[31]}},instruction[31:20]};
    wire [31:0] s_imm={{20{instruction[31]}},instruction[31:25],instruction[11:7]};
    wire [31:0] b_imm={{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
    wire [31:0] j_imm={{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};
    wire writeback=op==OP_LUI || op==OP_REG || op==OP_IMM || op==OP_LOAD || op==OP_JAL || op==OP_JALR;
    assign imem_addr=pc;
    assign dmem_addr=value;
    assign dmem_wdata=operand_b;
    assign dmem_we=rst_n && !halted && control[FINISH] && op==OP_STORE;
    assign dbg_rdata=regs[dbg_raddr];

    // ROM fields: optional load dispatch, next microaddress, datapath enables.
    function automatic [8:0] microinstruction(input logic [2:0] address);
        case (address)
            FETCH:   microinstruction={1'b0,3'd1,5'b00001};
            DECODE:  microinstruction={1'b0,3'd2,5'b00010};
            EXECUTE: microinstruction={1'b1,3'd4,5'b00100};
            MEMORY:  microinstruction={1'b0,3'd4,5'b01000};
            FINISH:  microinstruction={1'b0,3'd0,5'b10000};
            default: microinstruction={1'b0,3'd0,5'b00000};
        endcase
    endfunction
    wire [8:0] uword=microinstruction(micro_pc);
    always @* begin
        next_fsm=FETCH;
        next_micro=(uword[8] && op==OP_LOAD) ? MEMORY : uword[7:5];
        control=0;
        if (MICROCODE) control=uword[4:0];
        else case(fsm_state)
            FETCH:   begin control[FETCH]=1; next_fsm=DECODE; end
            DECODE:  begin control[DECODE]=1; next_fsm=EXECUTE; end
            EXECUTE: begin control[EXECUTE]=1; next_fsm=(op==OP_LOAD) ? MEMORY : FINISH; end
            MEMORY:  begin control[MEMORY]=1; next_fsm=FINISH; end
            FINISH:  begin control[FINISH]=1; next_fsm=FETCH; end
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_state<=FETCH; micro_pc<=FETCH; pc<=0; instruction<=0; operand_a<=0; operand_b<=0;
            value<=0; next_pc<=0; halted<=0; cycles<=0; retired<=0;
            for (integer i=0;i<32;i=i+1) regs[i]<=0;
        end else if (!halted) begin
            cycles<=cycles+1; fsm_state<=next_fsm; micro_pc<=next_micro;
            if (control[FETCH]) instruction<=imem_rdata;
            if (control[DECODE]) begin
                operand_a<=regs[instruction[19:15]]; operand_b<=regs[instruction[24:20]];
                next_pc<=pc+4;
            end
            if (control[EXECUTE]) begin
                case(op)
                    OP_LUI: value<={instruction[31:12],12'b0};
                    OP_IMM: begin
                        case(fn)
                            1: value<=operand_a<<instruction[24:20];
                            2: value<={31'b0,($signed(operand_a)<$signed(i_imm))};
                            4: value<=operand_a^i_imm;
                            5: value<=operand_a>>instruction[24:20];
                            6: value<=operand_a|i_imm;
                            7: value<=operand_a&i_imm;
                            default: value<=operand_a+i_imm;
                        endcase
                    end
                    OP_REG: begin
                        case(fn)
                            1: value<=operand_a<<operand_b[4:0];
                            2: value<={31'b0,($signed(operand_a)<$signed(operand_b))};
                            4: value<=operand_a^operand_b;
                            5: value<=operand_a>>operand_b[4:0];
                            6: value<=operand_a|operand_b;
                            7: value<=operand_a&operand_b;
                            default: value<=instruction[30] ? operand_a-operand_b : operand_a+operand_b;
                        endcase
                    end
                    OP_LOAD: value<=operand_a+i_imm;
                    OP_STORE: value<=operand_a+s_imm;
                    OP_BRANCH: if ((fn==0 && operand_a==operand_b) || (fn==1 && operand_a!=operand_b) || (fn==4 && $signed(operand_a)<$signed(operand_b)))
                        next_pc<=pc+b_imm;
                    OP_JAL: begin value<=pc+4; next_pc<=pc+j_imm; end
                    OP_JALR: begin value<=pc+4; next_pc<=(operand_a+i_imm)&32'hfffffffe; end
                    default: ;
                endcase
            end
            if (control[MEMORY]) value<=dmem_rdata;
            if (control[FINISH]) begin
                retired<=retired+1; pc<=next_pc;
                if (instruction==INSN_EBREAK) halted<=1;
                if (writeback && instruction[11:7]!=0) regs[instruction[11:7]]<=value;
            end
        end
    end
endmodule
