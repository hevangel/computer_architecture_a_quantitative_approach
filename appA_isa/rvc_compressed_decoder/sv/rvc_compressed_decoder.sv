// RV32C subset expander. Unsupported compressed encodings are flagged; all
// words whose low bits are 11 are passed through as 32-bit instructions.
module rvc_compressed_decoder (
    input logic [31:0] window,
    output logic [31:0] instruction,
    output logic [2:0] length_bytes,
    output logic illegal
);
    logic [15:0] c;
    logic [4:0] rd,rs1,rs2;
    logic [11:0] imm_i;
    logic [12:0] imm_b;
    logic [20:0] imm_j;
    always_comb begin
        c=window[15:0]; instruction=0; length_bytes=2; illegal=0;
        rd=0; rs1=0; rs2=0; imm_i=0; imm_b=0; imm_j=0;
        if (c[1:0]==2'b11) begin
            instruction=window; length_bytes=4;
        end else if (c[1:0]==2'b00 && (c[15:13]==3'b010 || c[15:13]==3'b110)) begin
            rs1={2'b01,c[9:7]}; rd={2'b01,c[4:2]};
            imm_i={5'b0,c[5],c[12:10],c[6],2'b00};
            if (c[15:13]==3'b010) instruction={imm_i,rs1,3'b010,rd,7'b0000011};
            else instruction={imm_i[11:5],rd,rs1,3'b010,imm_i[4:0],7'b0100011};
        end else if (c[1:0]==2'b01 && c[15:13]==3'b000) begin
            rd=c[11:7]; imm_i={{6{c[12]}},c[12],c[6:2]};
            instruction={imm_i,rd,3'b000,rd,7'b0010011};
        end else if (c[1:0]==2'b01 && c[15:13]==3'b110) begin
            rs1={2'b01,c[9:7]};
            imm_b={{4{c[12]}},c[12],c[6:5],c[2],c[11:10],c[4:3],1'b0};
            instruction={imm_b[12],imm_b[10:5],5'b0,rs1,3'b000,imm_b[4:1],imm_b[11],7'b1100011};
        end else if (c[1:0]==2'b01 && (c[15:13]==3'b101 || c[15:13]==3'b001)) begin
            rd=(c[15:13]==3'b001) ? 5'd1 : 5'd0;
            imm_j={{9{c[12]}},c[12],c[8],c[10:9],c[6],c[7],c[2],c[11],c[5:3],1'b0};
            instruction={imm_j[20],imm_j[10:1],imm_j[11],imm_j[19:12],rd,7'b1101111};
        end else if (c[1:0]==2'b10 && c[15:13]==3'b100 && c[6:2]!=0) begin
            rd=c[11:7]; rs2=c[6:2]; rs1=c[12] ? rd : 0;
            instruction={7'b0,rs2,rs1,3'b000,rd,7'b0110011};
        end else illegal=1;
    end
endmodule

module rvc_fetch (
    input logic [31:0] pc, window,
    output logic [31:0] instruction, next_pc,
    output logic [2:0] length_bytes,
    output logic illegal
);
    rvc_compressed_decoder decoder(window,instruction,length_bytes,illegal);
    always_comb next_pc=pc+length_bytes;
endmodule
