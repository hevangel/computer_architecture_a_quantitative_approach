// One word per line; ideal backing memory is a pure function of line address.
// All cache probes and four prefetch fills complete in the request clock cycle.
module stream_buffer (
    input logic clk, reset, req_valid, prefetch_enable,
    input logic [31:0] req_line,
    output logic response_valid,
    output logic [31:0] response_data,
    output logic [31:0] cycles, l1_hits, l1_misses, demand_reads, prefetch_hits, prefetch_reads
);
    logic [7:0] l1_valid;
    logic [31:0] l1_tag [0:7], l1_data [0:7];
    logic fifo_valid;
    logic [31:0] fifo_tag [0:3], fifo_data [0:3];
    integer i;
    function automatic [31:0] memory_data(input [31:0] address);
        memory_data = address ^ 32'ha5c39e71;
    endfunction
    always_ff @(posedge clk) begin
        if (reset) begin
            l1_valid <= 0; fifo_valid <= 0; response_valid <= 0; response_data <= 0;
            cycles <= 0; l1_hits <= 0; l1_misses <= 0; demand_reads <= 0;
            prefetch_hits <= 0; prefetch_reads <= 0;
            for (i=0;i<8;i=i+1) begin l1_tag[i] <= 0; l1_data[i] <= 0; end
            for (i=0;i<4;i=i+1) begin fifo_tag[i] <= 0; fifo_data[i] <= 0; end
        end else begin
            cycles <= cycles + 1;
            response_valid <= req_valid;
            if (!prefetch_enable) fifo_valid <= 0;
            if (req_valid) begin
                if (l1_valid[req_line[2:0]] && l1_tag[req_line[2:0]] == req_line) begin
                    l1_hits <= l1_hits + 1;
                    response_data <= l1_data[req_line[2:0]];
                end else begin
                    l1_misses <= l1_misses + 1;
                    l1_valid[req_line[2:0]] <= 1;
                    l1_tag[req_line[2:0]] <= req_line;
                    if (prefetch_enable && fifo_valid && fifo_tag[0] == req_line) begin
                        prefetch_hits <= prefetch_hits + 1;
                        response_data <= fifo_data[0];
                        l1_data[req_line[2:0]] <= fifo_data[0];
                        for (i=0;i<3;i=i+1) begin fifo_tag[i] <= fifo_tag[i+1]; fifo_data[i] <= fifo_data[i+1]; end
                        fifo_tag[3] <= fifo_tag[3] + 1;
                        fifo_data[3] <= memory_data(fifo_tag[3] + 1);
                        prefetch_reads <= prefetch_reads + 1;
                    end else begin
                        demand_reads <= demand_reads + 1;
                        response_data <= memory_data(req_line);
                        l1_data[req_line[2:0]] <= memory_data(req_line);
                        if (prefetch_enable) begin
                            fifo_valid <= 1;
                            for (i=0;i<4;i=i+1) begin
                                fifo_tag[i] <= req_line + i + 1;
                                fifo_data[i] <= memory_data(req_line + i + 1);
                            end
                            prefetch_reads <= prefetch_reads + 4;
                        end
                    end
                end
            end
        end
    end
endmodule
