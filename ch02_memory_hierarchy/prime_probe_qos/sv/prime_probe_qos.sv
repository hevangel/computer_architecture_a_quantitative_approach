// One set, four ways, FIFO replacement. The partition setting is captured on
// reset so that changing security domains cannot expose stale cached state.
module prime_probe_qos #(parameter HIT_CYCLES=1, MISS_CYCLES=5) (
    input logic clk, reset, partition_enable,
    input logic req_valid, domain_id, input logic [31:0] line_address,
    output logic req_ready, response_valid, response_hit,
    output logic [31:0] response_latency, spy_hits, spy_misses
);
    logic partitioned;
    logic [3:0] valid_bits;
    logic [31:0] tags [0:3];
    logic [1:0] next_shared;
    logic next_victim, next_spy;
    integer remaining, i, found, chosen;
    assign req_ready = (remaining == 0);
    always_ff @(posedge clk) begin
        if (reset) begin
            partitioned <= partition_enable; valid_bits <= 0; next_shared <= 0;
            next_victim <= 0; next_spy <= 0; remaining <= 0;
            response_valid <= 0; response_hit <= 0; response_latency <= 0;
            spy_hits <= 0; spy_misses <= 0;
            for (i=0;i<4;i=i+1) tags[i] <= 0;
        end else begin
            response_valid <= 0;
            if (remaining != 0) begin
                remaining <= remaining - 1;
                if (remaining == 1) response_valid <= 1;
            end else if (req_valid) begin
                found = -1;
                for (i=0;i<4;i=i+1)
                    if ((!partitioned || (domain_id ? i>=2 : i<2)) && valid_bits[i] && tags[i]==line_address)
                        found = i;
                if (found >= 0) begin
                    response_hit <= 1; response_latency <= HIT_CYCLES; remaining <= HIT_CYCLES;
                    if (domain_id) spy_hits <= spy_hits + 1;
                end else begin
                    if (!partitioned) begin chosen = next_shared; next_shared <= next_shared + 1'b1; end
                    else if (domain_id) begin chosen = 2 + next_spy; next_spy <= ~next_spy; end
                    else begin chosen = next_victim; next_victim <= ~next_victim; end
                    tags[chosen] <= line_address; valid_bits[chosen] <= 1;
                    response_hit <= 0; response_latency <= MISS_CYCLES; remaining <= MISS_CYCLES;
                    if (domain_id) spy_misses <= spy_misses + 1;
                end
            end
        end
    end
endmodule
