// Two-core, two-address SC/TSO teaching machine. One command is presented per
// cycle; a FENCE drains at most one queued store per retry, then acknowledges.
module consistency_litmus_tsosb (
    input logic clk, reset, mode_tso,
    input logic cmd_valid, core_id, input logic [1:0] cmd,
    input logic address, input logic [31:0] write_data,
    output logic accepted, read_valid, output logic [31:0] read_data,
    output logic [31:0] mem_x, mem_y,
    output logic [1:0] pending_core0, pending_core1
);
    localparam STORE=2'd0, LOAD=2'd1, DRAIN=2'd2, FENCE=2'd3;
    logic tso;
    logic [31:0] memory [0:1];
    logic [31:0] data_q [0:1][0:1];
    logic addr_q [0:1][0:1];
    logic [1:0] count [0:1];
    integer c;
    assign mem_x=memory[0]; assign mem_y=memory[1];
    assign pending_core0=count[0]; assign pending_core1=count[1];
    always_ff @(posedge clk) begin
        if (reset) begin
            tso<=mode_tso; accepted<=0; read_valid<=0; read_data<=0;
            for (c=0;c<2;c=c+1) begin
                memory[c]<=0; count[c]<=0;
                addr_q[c][0]<=0; addr_q[c][1]<=0; data_q[c][0]<=0; data_q[c][1]<=0;
            end
        end else begin
            accepted<=0; read_valid<=0;
            if (cmd_valid) begin
                case (cmd)
                    STORE: begin
                        if (!tso) begin memory[address]<=write_data; accepted<=1; end
                        else if (count[core_id]<2) begin
                            addr_q[core_id][count[core_id]]<=address;
                            data_q[core_id][count[core_id]]<=write_data;
                            count[core_id]<=count[core_id]+1'b1; accepted<=1;
                        end
                    end
                    LOAD: begin
                        if (tso && count[core_id]==2 && addr_q[core_id][1]==address) read_data<=data_q[core_id][1];
                        else if (tso && count[core_id]!=0 && addr_q[core_id][0]==address) read_data<=data_q[core_id][0];
                        else read_data<=memory[address];
                        accepted<=1; read_valid<=1;
                    end
                    DRAIN, FENCE: begin
                        if (count[core_id]!=0) begin
                            memory[addr_q[core_id][0]]<=data_q[core_id][0];
                            addr_q[core_id][0]<=addr_q[core_id][1];
                            data_q[core_id][0]<=data_q[core_id][1];
                            count[core_id]<=count[core_id]-1'b1;
                            if (cmd==DRAIN) accepted<=1;
                        end else accepted<=1;
                    end
                endcase
            end
        end
    end
endmodule
