`timescale 1ns/1ps
module tb_rvc_compressed_decoder;
    logic [31:0] pc=0, window=0;
    wire [31:0] instruction,next_pc;
    wire [2:0] length_bytes;
    wire illegal;
    integer fd,rc,c,expected_c,expected_illegal,steps,bytes,rd,rs1,immediate;
    logic [31:0] expected_word;
    logic [15:0] mem [0:9];
    logic [31:0] regs [0:31];
    rvc_fetch dut(pc,window,instruction,next_pc,length_bytes,illegal);
    initial begin
        fd=$fopen("../../../../appA_isa/rvc_compressed_decoder/golden.txt","r");
        if (!fd) $fatal(1,"TEST FAILED: missing golden vectors");
        pc=100;
        for (c=0;c<65536;c=c+1) begin
            if ((c&3)!=3) begin
                rc=$fscanf(fd,"%h %h %d\n",expected_c,expected_word,expected_illegal);
                if (rc!=3 || expected_c!=c) $fatal(1,"TEST FAILED: vector file");
                window={16'hfa05,c[15:0]}; #1;
                if (length_bytes!==2 || next_pc!==102 || illegal!==expected_illegal[0] || instruction!==expected_word)
                    $fatal(1,"TEST FAILED: compressed %h expected %h got %h",c[15:0],expected_word,instruction);
            end
        end
        $fclose(fd);
        window=32'h123456f3; #1;
        if (illegal || length_bytes!==4 || instruction!==window || next_pc!==104) $fatal(1,"TEST FAILED: passthrough");
        // 18-byte loop: addi x8,3; c.addi x8,-1; addi x9,1;
        // c.beqz x8,+4; c.j -8; addi x10,x9,0. Compare with 24-byte RV32I.
        mem[0]=16'h0413; mem[1]=16'h0030; mem[2]=16'h147d; mem[3]=16'h8493; mem[4]=16'h0014;
        mem[5]=16'hc011; mem[6]=16'hbfe5; mem[7]=16'h8513; mem[8]=16'h0004; mem[9]=0;
        for (c=0;c<32;c=c+1) regs[c]=0;
        pc=0; steps=0; bytes=0;
        while (pc<18 && steps<50) begin
            window={mem[(pc>>1)+1],mem[pc>>1]}; #1;
            if (illegal) $fatal(1,"TEST FAILED: loop decode");
            steps=steps+1; bytes=bytes+length_bytes;
            rd=instruction[11:7]; rs1=instruction[19:15];
            case (instruction[6:0])
                7'h13: begin
                    immediate=$signed({{20{instruction[31]}},instruction[31:20]});
                    if (rd!=0) regs[rd]=regs[rs1]+immediate;
                    pc=next_pc;
                end
                7'h63: begin
                    immediate=$signed({{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0});
                    if (regs[rs1]==0) pc=pc+immediate; else pc=next_pc;
                end
                7'h6f: begin
                    immediate=$signed({{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0});
                    if (rd!=0) regs[rd]=next_pc;
                    pc=pc+immediate;
                end
                default: $fatal(1,"TEST FAILED: loop opcode");
            endcase
        end
        if (pc!=18 || regs[8]!=0 || regs[9]!=3 || regs[10]!=3 || steps!=13 || bytes!=36)
            $fatal(1,"TEST FAILED: loop result");
        $display("TEST PASSED"); $finish;
    end
endmodule
