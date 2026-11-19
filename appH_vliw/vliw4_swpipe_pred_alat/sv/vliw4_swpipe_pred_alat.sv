module vliw4_swpipe_pred_alat(
    input logic clk, rst_n,
    output wire [31:0] imem_addr,
    input logic [127:0] imem_rdata,
    output logic [31:0] dmem_addr, dmem_wdata,
    output logic dmem_we,
    input logic [31:0] dmem_rdata,
    input logic dmem_fault,
    input logic [3:0] dbg_raddr,
    output wire [31:0] dbg_rdata,
    output wire dbg_nat,
    output logic halted,
    output logic [2:0] trap_cause,
    output logic [31:0] bundles, ops, alat_failures
);
    localparam integer ADD=1,SUB=2,MUL=3,ADDI=4,LD=5,ST=6,BNEZ=7,JMP=8,
        LDS=9,LDA=10,CHKS=11,CHKA=12,PSET=13,ROTBR=14,HALT=15;
    logic [31:0] regs [0:15];
    logic [15:0] nat;
    logic [7:0] predicates;
    logic [31:0] pc;
    logic rotated;
    logic [3:0] alat_valid;
    logic [3:0] alat_rd [0:3];
    logic [31:0] alat_addr [0:3];
    logic [1:0] alat_next;
    logic load_pending, load_nat;
    logic [3:0] load_rd;
    logic [31:0] load_value;
    logic [3:0] opc [0:3], rd [0:3], ra [0:3], rb [0:3], raw_rd [0:3];
    logic [31:0] immediate [0:3];
    logic [31:0] alu [0:1];
    logic [1:0] alu_write, alu_nat, predicate_write, predicate_value;
    logic issue_load, issue_store, rotate_now, stop_now, check_failed;
    logic [31:0] next_pc, bundle_ops;
    logic [2:0] trap_now;

    function automatic [3:0] physical(input logic [3:0] reg_id,input logic bank);
        physical=(bank && reg_id[3]) ? reg_id ^ 4'h4 : reg_id;
    endfunction
    function automatic logic overlaps(input logic [31:0] a,b);
        overlaps=({1'b0,a}<({1'b0,b}+4)) && ({1'b0,b}<({1'b0,a}+4));
    endfunction
    assign imem_addr=pc;
    assign dbg_rdata=regs[physical(dbg_raddr,rotated)];
    assign dbg_nat=nat[physical(dbg_raddr,rotated)];

    always @* begin : decode
        logic [31:0] op_word;
        logic guard_on, found;
        bundle_ops=0; alu_write=0; alu_nat=0; predicate_write=0; predicate_value=0;
        issue_load=0; issue_store=0; rotate_now=0; stop_now=0; check_failed=0; trap_now=0;
        next_pc=pc+1;
        for (integer i=0;i<4;i=i+1) begin
            op_word=imem_rdata[32*i +: 32];
            guard_on=predicates[op_word[15:13]] ^ op_word[12];
            opc[i]=guard_on ? op_word[31:28] : 0;
            raw_rd[i]=op_word[27:24];
            rd[i]=physical(raw_rd[i],rotated);
            ra[i]=physical(op_word[23:20],rotated);
            rb[i]=physical(op_word[19:16],rotated);
            immediate[i]={{20{op_word[11]}},op_word[11:0]};
        end
        for (integer i=0;i<2;i=i+1) begin
            alu[i]=0;
            case(opc[i])
                ADD: begin alu[i]=regs[ra[i]]+regs[rb[i]]; alu_write[i]=1; end
                SUB: begin alu[i]=regs[ra[i]]-regs[rb[i]]; alu_write[i]=1; end
                MUL: begin alu[i]=regs[ra[i]]*regs[rb[i]]; alu_write[i]=1; end
                ADDI: begin alu[i]=regs[ra[i]]+immediate[i]; alu_write[i]=1; end
                PSET: begin
                    predicate_write[i]=1;
                    predicate_value[i]=(regs[ra[i]]==regs[rb[i]]) ^ immediate[i][0];
                    if (nat[ra[i]] || nat[rb[i]]) trap_now=2;
                end
                default: ;
            endcase
            if (alu_write[i]) alu_nat[i]=nat[ra[i]] || (opc[i]!=ADDI && nat[rb[i]]);
            if (alu_write[i] || predicate_write[i]) bundle_ops=bundle_ops+1;
        end
        dmem_addr=regs[ra[2]]+immediate[2]; dmem_wdata=regs[rb[2]];
        issue_load=(opc[2]==LD || opc[2]==LDS || opc[2]==LDA);
        issue_store=(opc[2]==ST);
        if (issue_load || issue_store) bundle_ops=bundle_ops+1;
        if ((issue_load && opc[2]!=LDS && (dmem_fault || nat[ra[2]])) ||
            (issue_store && (dmem_fault || nat[ra[2]] || nat[rb[2]]))) trap_now=1;
        case(opc[3])
            BNEZ,ROTBR: begin
                if (nat[ra[3]]) trap_now=2;
                else if (regs[ra[3]]!=0) next_pc=immediate[3];
                rotate_now=(opc[3]==ROTBR);
                bundle_ops=bundle_ops+1;
            end
            JMP: begin next_pc=immediate[3]; bundle_ops=bundle_ops+1; end
            CHKS: begin if (nat[ra[3]]) trap_now=2; bundle_ops=bundle_ops+1; end
            CHKA: begin
                found=0;
                for(integer i=0;i<4;i=i+1)
                    if (alat_valid[i] && alat_rd[i]==ra[3] &&
                        !(issue_store && overlaps(alat_addr[i],dmem_addr))) found=1;
                check_failed=!found;
                if (!found) next_pc=immediate[3];
                bundle_ops=bundle_ops+1;
            end
            HALT: begin stop_now=1; bundle_ops=bundle_ops+1; end
            default: ;
        endcase
        dmem_we=rst_n && !halted && issue_store && trap_now==0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pc<=0; rotated<=0; predicates<=1; nat<=0; halted<=0; trap_cause<=0;
            load_pending<=0; load_nat<=0; load_rd<=0; load_value<=0;
            bundles<=0; ops<=0; alat_failures<=0; alat_valid<=0; alat_next<=0;
            for(integer i=0;i<16;i=i+1) regs[i]<=0;
            for(integer i=0;i<4;i=i+1) begin alat_rd[i]<=0; alat_addr[i]<=0; end
        end else if (!halted) begin
            if (load_pending && load_rd!=0) begin regs[load_rd]<=load_value; nat[load_rd]<=load_nat; end
            load_pending<=0;
            bundles<=bundles+1;
            if (trap_now!=0) begin halted<=1; trap_cause<=trap_now; end
            else begin
                ops<=ops+bundle_ops;
                for(integer i=0;i<2;i=i+1) begin
                    if (alu_write[i] && rd[i]!=0) begin regs[rd[i]]<=alu[i]; nat[rd[i]]<=alu_nat[i]; end
                    if (predicate_write[i] && raw_rd[i][2:0]!=0)
                        predicates[raw_rd[i][2:0]]<=predicate_value[i];
                end
                for(integer i=0;i<4;i=i+1)
                    if ((issue_store && overlaps(alat_addr[i],dmem_addr)) ||
                        (issue_load && rd[2]==alat_rd[i]) ||
                        (alu_write[0] && rd[0]==alat_rd[i]) ||
                        (alu_write[1] && rd[1]==alat_rd[i])) alat_valid[i]<=0;
                if (issue_load) begin
                    load_pending<=1; load_rd<=rd[2];
                    load_nat<=opc[2]==LDS && (dmem_fault || nat[ra[2]]);
                    load_value<=(dmem_fault || nat[ra[2]]) ? 0 : dmem_rdata;
                    if (opc[2]==LDA && rd[2]!=0) begin
                        alat_valid[alat_next]<=1; alat_rd[alat_next]<=rd[2];
                        alat_addr[alat_next]<=dmem_addr; alat_next<=alat_next+1;
                    end
                end
                if (check_failed) alat_failures<=alat_failures+1;
                if (rotate_now) rotated<=!rotated;
                if (stop_now) halted<=1;
                pc<=next_pc;
            end
        end
    end
endmodule
