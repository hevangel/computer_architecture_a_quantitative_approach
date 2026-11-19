// Four-line read-only direct-mapped tag-and-data cache with an optional
// one-cycle two-bit miss predictor and a single outstanding request.
module alloy_dram_cache #(
    parameter PREDICT_ENABLE=1, TAG_CYCLES=30, DATA_CYCLES=4, MEMORY_CYCLES=100, PREDICT_CYCLES=1
) (
    input logic clk, reset, req_valid,
    input logic [31:0] line_address, input logic [1:0] predictor_index,
    output logic req_ready, response_valid, response_hit, predicted_hit,
    output logic [31:0] response_data, response_latency,
    output logic [31:0] hits, misses, correct_hit, correct_miss, false_hit, false_miss, backing_reads
);
    logic [3:0] valid_bits;
    logic [31:0] tags [0:3], data [0:3];
    logic [1:0] prediction [0:3];
    integer remaining, i, chosen_latency;
    logic actual, predicted;
    assign req_ready = remaining==0;
    function automatic [31:0] memory_data(input [31:0] address);
        memory_data = address ^ 32'hc39a57e1;
    endfunction
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_bits<=0; remaining<=0; response_valid<=0; response_hit<=0; predicted_hit<=0;
            response_data<=0; response_latency<=0; hits<=0; misses<=0;
            correct_hit<=0; correct_miss<=0; false_hit<=0; false_miss<=0; backing_reads<=0;
            for (i=0;i<4;i=i+1) begin tags[i]<=0; data[i]<=0; prediction[i]<=1; end
        end else begin
            response_valid<=0;
            if (remaining!=0) begin
                remaining<=remaining-1;
                if (remaining==1) response_valid<=1;
            end else if (req_valid) begin
                actual=valid_bits[line_address[1:0]] && tags[line_address[1:0]]==line_address;
                predicted=prediction[predictor_index][1];
                response_hit<=actual; predicted_hit<=predicted;
                if (actual) begin
                    hits<=hits+1; response_data<=data[line_address[1:0]];
                    chosen_latency=TAG_CYCLES+DATA_CYCLES;
                    if (prediction[predictor_index]!=3) prediction[predictor_index]<=prediction[predictor_index]+1'b1;
                end else begin
                    misses<=misses+1; response_data<=memory_data(line_address);
                    valid_bits[line_address[1:0]]<=1; tags[line_address[1:0]]<=line_address;
                    data[line_address[1:0]]<=memory_data(line_address);
                    if (PREDICT_ENABLE && !predicted) begin
                        if (PREDICT_CYCLES+MEMORY_CYCLES>TAG_CYCLES) chosen_latency=PREDICT_CYCLES+MEMORY_CYCLES;
                        else chosen_latency=TAG_CYCLES;
                    end else chosen_latency=TAG_CYCLES+MEMORY_CYCLES;
                    if (prediction[predictor_index]!=0) prediction[predictor_index]<=prediction[predictor_index]-1'b1;
                end
                if (actual && predicted) correct_hit<=correct_hit+1;
                else if (!actual && !predicted) correct_miss<=correct_miss+1;
                else if (!actual && predicted) false_hit<=false_hit+1;
                else false_miss<=false_miss+1;
                if (!actual || (PREDICT_ENABLE && !predicted)) backing_reads<=backing_reads+1;
                response_latency<=chosen_latency; remaining<=chosen_latency;
            end
        end
    end
endmodule
