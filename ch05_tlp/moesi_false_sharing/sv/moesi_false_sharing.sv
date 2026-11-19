module moesi_false_sharing (
    input logic clk, reset, valid, write,
    input logic [1:0] core,
    input logic [3:0] address, // eight lines, two words each
    input logic [31:0] write_word,
    output logic [31:0] read_word,
    output logic [2:0] miss_kind, // 0 hit, 1 cold, 2 capacity, 3 conflict, 4 true, 5 false
    output logic [31:0] memory_writes, peer_dirty_reads, false_misses,
    output logic [2:0] requester_state,
    output wire [23:0] cache_states
);
    localparam logic [2:0] I=0, S=1, E=2, M=3, O=4;
    logic [2:0] state [0:3][0:1];
    logic [2:0] tag [0:3][0:1];
    logic [63:0] data [0:3][0:1], backing [0:7];
    logic [7:0] seen [0:3];
    logic [1:0] invalid_words [0:3][0:7];
    integer recent [0:3], older [0:3];
    genvar c, set_index;
    generate
        for (c=0; c<4; c=c+1) begin : cores
            for (set_index=0; set_index<2; set_index=set_index+1) begin : sets
                assign cache_states[6*c+3*set_index +: 3]=state[c][set_index];
            end
        end
    endgenerate
    always @(posedge clk) begin : snoop
        integer i, k, line_num, slot;
        logic matching, shared_copy;
        logic [63:0] fill;
        logic [2:0] category;
        if (reset) begin
            memory_writes <= 0; peer_dirty_reads <= 0; false_misses <= 0;
            requester_state <= I; read_word <= 0; miss_kind <= 0;
            for (i=0;i<4;i=i+1) begin
                seen[i]=0; recent[i]=-1; older[i]=-1;
                for (k=0;k<8;k=k+1) invalid_words[i][k]=0;
                for (k=0;k<2;k=k+1) begin state[i][k]=I; tag[i][k]=0; data[i][k]=0; end
            end
            for (k=0;k<8;k=k+1) backing[k]=0;
        end else if (valid) begin
            line_num=int'(address[3:1]); slot=line_num%2;
            matching=state[core][slot]!=I && tag[core][slot]==line_num;
            category=0;
            if (!matching) begin
                // Prior coherence loss takes precedence over the 3C shadow.
                if (invalid_words[core][line_num]!=0)
                    category=invalid_words[core][line_num][address[0]] ? 4 : 5;
                else if (!seen[core][line_num]) category=1;
                else if (recent[core]!=line_num && older[core]!=line_num) category=2;
                else category=3;
                if (category==5) false_misses <= false_misses+1;
                if (state[core][slot]==M || state[core][slot]==O) begin
                    backing[tag[core][slot]]=data[core][slot];
                    memory_writes <= memory_writes+1;
                end
                fill=backing[line_num];
                shared_copy=0;
                for (i=0;i<4;i=i+1) begin
                    if (i!=int'(core) && state[i][slot]!=I && tag[i][slot]==line_num) begin
                        shared_copy=1;
                        if (state[i][slot]==M || state[i][slot]==O) begin
                            fill=data[i][slot];
                            if (!write) peer_dirty_reads <= peer_dirty_reads+1;
                            state[i][slot]=O;
                        end else if (state[i][slot]==E) state[i][slot]=S;
                    end
                end
                data[core][slot]=fill; tag[core][slot]=line_num;
                state[core][slot]=shared_copy ? S : E;
            end
            if (write) begin
                for (i=0;i<4;i=i+1) begin
                    if (i!=int'(core)) begin
                        if (state[i][slot]!=I && tag[i][slot]==line_num) begin
                            state[i][slot]=I;
                            invalid_words[i][line_num][address[0]]=1;
                        end else if (invalid_words[i][line_num]!=0)
                            invalid_words[i][line_num][address[0]]=1;
                    end
                end
                state[core][slot]=M;
                data[core][slot][32*address[0] +: 32]=write_word;
            end
            seen[core][line_num]=1;
            invalid_words[core][line_num]=0;
            if (recent[core]!=line_num) begin older[core]=recent[core]; recent[core]=line_num; end
            miss_kind <= category;
            requester_state <= state[core][slot];
            read_word <= data[core][slot][32*address[0] +: 32];
        end
    end
endmodule
