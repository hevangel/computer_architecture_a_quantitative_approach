// Work-in-progress two-thread rename and issue engine. See README for scope.
module smt_multithread_core #(
    parameter integer MODE = 3, // 0 single, 1 coarse, 2 fine, 3 SMT
    parameter integer NPHYS = 20,
    parameter integer ROB_SIZE = 8,
    parameter integer PROGRAM_SIZE = 64,
    parameter integer LOAD_LATENCY = 7,
    parameter integer MUL_LATENCY = 4
)(
    input logic clk, reset,
    input logic prog_we, prog_thread,
    input logic [1:0] prog_op, // 0 add, 1 multiply, 2 load
    input logic [2:0] prog_dst, prog_src,
    input logic [31:0] prog_arg,
    input logic mem_we,
    input logic [7:0] mem_addr,
    input logic [31:0] mem_data,
    input logic start,
    input logic read_thread,
    input logic [2:0] read_reg,
    output logic [31:0] read_value,
    output wire prog_ready,
    output logic done,
    output integer cycles, issued, switches
);
    logic [1:0] program_op [0:1][0:PROGRAM_SIZE-1];
    logic [2:0] program_dst [0:1][0:PROGRAM_SIZE-1], program_src [0:1][0:PROGRAM_SIZE-1];
    logic [31:0] program_arg [0:1][0:PROGRAM_SIZE-1];
    logic [31:0] memory [0:255];
    integer length [0:1], pc [0:1];
    logic [31:0] prf [0:1][0:NPHYS-1];
    logic ready [0:1][0:NPHYS-1], free_phys [0:1][0:NPHYS-1];
    integer front [0:1][0:7], committed [0:1][0:7];
    integer head [0:1], count [0:1];
    logic [1:0] rob_op [0:1][0:ROB_SIZE-1];
    integer rob_src [0:1][0:ROB_SIZE-1], rob_dst [0:1][0:ROB_SIZE-1];
    integer rob_old [0:1][0:ROB_SIZE-1], rob_arch [0:1][0:ROB_SIZE-1];
    logic [31:0] rob_arg [0:1][0:ROB_SIZE-1], rob_value [0:1][0:ROB_SIZE-1];
    logic rob_issued [0:1][0:ROB_SIZE-1], rob_done [0:1][0:ROB_SIZE-1];
    integer rob_due [0:1][0:ROB_SIZE-1];
    integer active, rr;
    logic running;
    integer t, p, k, idx, tail, dest, slot, chosen, candidate_idx;
    integer src_tag, arch, old_tag, other_idx;
    logic mem_available, switching;
    logic [31:0] operand, value, address;


    assign prog_ready = !reset && !running && !done && length[prog_thread] < PROGRAM_SIZE;

    // Oldest not-yet-issued entry is the sole candidate for each thread.
    function automatic integer candidate(input integer thread_id, input logic mem_ok);
        integer q, n, pos, result;
        begin
            result = -1;
            n = 0;
            while (n < count[thread_id] && result == -1) begin
                pos = (head[thread_id] + n) % ROB_SIZE;
                if (!rob_issued[thread_id][pos]) begin
                    if (ready[thread_id][rob_src[thread_id][pos]] &&
                        (mem_ok || rob_op[thread_id][pos] != 2)) result = pos;
                    else result = -2;
                end
                n = n + 1;
            end
            if (result < 0) candidate = -1; else candidate = result;
        end
    endfunction

    function automatic logic thread_done(input integer thread_id);
        thread_done = (pc[thread_id] == length[thread_id] && count[thread_id] == 0);
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            running = 0; done = 0; cycles = 0; issued = 0; switches = 0;
            active = 0; rr = 0;
            for (t=0;t<2;t=t+1) begin
                length[t]=0; pc[t]=0; head[t]=0; count[t]=0;
                for (p=0;p<NPHYS;p=p+1) begin
                    prf[t][p]=0; ready[t][p]=1; free_phys[t][p]=(p>=8);
                end
                for (p=0;p<8;p=p+1) begin front[t][p]=p; committed[t][p]=p; end
                for (p=0;p<ROB_SIZE;p=p+1) begin rob_issued[t][p]=0; rob_done[t][p]=0; end
            end
            for (p=0;p<256;p=p+1) memory[p]=0;
        end else if (!running && !done) begin
            if (prog_we && prog_ready) begin
                program_op[prog_thread][length[prog_thread]]=prog_op;
                program_dst[prog_thread][length[prog_thread]]=prog_dst;
                program_src[prog_thread][length[prog_thread]]=prog_src;
                program_arg[prog_thread][length[prog_thread]]=prog_arg;
                length[prog_thread]=length[prog_thread]+1;
            end
            if (mem_we) memory[mem_addr]=mem_data;
            if (start) running=1;
        end else if (running) begin
            // Complete all execution pipes before retirement/dispatch/issue.
            for (t=0;t<2;t=t+1) begin
                for (k=0;k<count[t];k=k+1) begin
                    idx=(head[t]+k)%ROB_SIZE;
                    if (rob_issued[t][idx] && !rob_done[t][idx] && rob_due[t][idx]==cycles) begin
                        prf[t][rob_dst[t][idx]]=rob_value[t][idx];
                        ready[t][rob_dst[t][idx]]=1;
                        rob_done[t][idx]=1;
                    end
                end
                for (slot=0;slot<2;slot=slot+1) begin
                    if (count[t]>0 && rob_done[t][head[t]]) begin
                        idx=head[t];
                        committed[t][rob_arch[t][idx]]=rob_dst[t][idx];
                        free_phys[t][rob_old[t][idx]]=1;
                        head[t]=(head[t]+1)%ROB_SIZE;
                        count[t]=count[t]-1;
                    end
                end
                for (slot=0;slot<2;slot=slot+1) begin
                    dest=-1;
                    for (p=0;p<NPHYS;p=p+1)
                        if (free_phys[t][p] && dest==-1) dest=p;
                    if (pc[t]<length[t] && count[t]<ROB_SIZE && dest>=0) begin
                        tail=(head[t]+count[t])%ROB_SIZE;
                        arch=program_dst[t][pc[t]];
                        src_tag=front[t][program_src[t][pc[t]]];
                        old_tag=front[t][arch];
                        free_phys[t][dest]=0; ready[t][dest]=0;
                        front[t][arch]=dest;
                        rob_op[t][tail]=program_op[t][pc[t]];
                        rob_src[t][tail]=src_tag; rob_dst[t][tail]=dest;
                        rob_old[t][tail]=old_tag; rob_arch[t][tail]=arch;
                        rob_arg[t][tail]=program_arg[t][pc[t]];
                        rob_issued[t][tail]=0; rob_done[t][tail]=0;
                        pc[t]=pc[t]+1; count[t]=count[t]+1;
                    end
                end
            end
            if (MODE==0 && thread_done(0)) active=1;
            switching=0;
            if (MODE==1 && candidate(active,1)==-1 && !thread_done(1-active) && candidate(1-active,1)!=-1) begin
                active=1-active; switches=switches+1; switching=1;
            end
            if (!switching) begin
                if (MODE==2) chosen=cycles%2;
                else if (MODE==3) chosen=rr;
                else chosen=active;
                mem_available=1;
                for (slot=0;slot<2;slot=slot+1) begin
                    candidate_idx=candidate(chosen,mem_available);
                    if (MODE==3 && candidate_idx==-1) begin
                        chosen=1-chosen; candidate_idx=candidate(chosen,mem_available);
                    end
                    if (candidate_idx>=0) begin
                        operand=prf[chosen][rob_src[chosen][candidate_idx]];
                        case (rob_op[chosen][candidate_idx])
                            0: begin value=operand+rob_arg[chosen][candidate_idx]; rob_due[chosen][candidate_idx]=cycles+1; end
                            1: begin value=operand*rob_arg[chosen][candidate_idx]; rob_due[chosen][candidate_idx]=cycles+MUL_LATENCY; end
                            default: begin
                                address=operand+rob_arg[chosen][candidate_idx];
                                value=memory[address[7:0]]; rob_due[chosen][candidate_idx]=cycles+LOAD_LATENCY; mem_available=0;
                            end
                        endcase
                        rob_value[chosen][candidate_idx]=value;
                        rob_issued[chosen][candidate_idx]=1;
                        issued=issued+1;
                        if (MODE==3) chosen=1-chosen;
                    end
                end
                if (MODE==3) rr=1-rr;
            end
            cycles=cycles+1;
            if (thread_done(0) && thread_done(1)) begin running=0; done=1; end
        end
        read_value = prf[read_thread][committed[read_thread][read_reg]];
    end
endmodule
