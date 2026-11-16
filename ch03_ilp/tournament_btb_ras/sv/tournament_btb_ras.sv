// Non-speculative 2-bit local/global tournament predictor, direct-mapped BTB,
// and four-entry return stack. Query and resolution use the same PC.
module tournament_btb_ras (
    input logic clk, reset, input logic [31:0] pc,
    input logic update_valid, input logic [1:0] update_kind, // 0 branch, 1 call, 2 return
    input logic actual_taken, input logic [31:0] actual_target,
    output logic local_taken, global_taken, tournament_taken,
    output logic btb_hit, output logic [31:0] btb_target,
    output logic ras_valid, output logic [31:0] ras_target
);
    logic [1:0] local_history [0:3], local_table [0:15], global_table [0:3], selector [0:3];
    logic [1:0] global_history;
    logic [3:0] btb_valid;
    logic [31:0] btb_tag [0:3], btb_value [0:3], stack [0:3];
    logic [2:0] stack_count;
    wire [1:0] idx = pc[3:2];
    wire [3:0] local_index = {idx, local_history[idx]};
    integer i;
    function automatic [1:0] update_counter(input [1:0] value, input logic taken);
        if (taken) update_counter = value==3 ? 3 : value+1'b1;
        else update_counter = value==0 ? 0 : value-1'b1;
    endfunction
    always_comb begin
        local_taken = local_table[local_index][1];
        global_taken = global_table[global_history][1];
        tournament_taken = selector[idx][1] ? global_taken : local_taken;
        btb_hit = btb_valid[idx] && btb_tag[idx] == pc;
        btb_target = btb_hit ? btb_value[idx] : 0;
        ras_valid = stack_count != 0;
        ras_target = ras_valid ? stack[stack_count-1] : 0;
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            global_history <= 0; btb_valid <= 0; stack_count <= 0;
            for (i=0;i<4;i=i+1) begin
                local_history[i] <= 0; global_table[i] <= 1; selector[i] <= 1;
                btb_tag[i] <= 0; btb_value[i] <= 0; stack[i] <= 0;
            end
            for (i=0;i<16;i=i+1) local_table[i] <= 1;
        end else if (update_valid) begin
            if (update_kind == 0) begin
                local_table[local_index] <= update_counter(local_table[local_index],actual_taken);
                global_table[global_history] <= update_counter(global_table[global_history],actual_taken);
                if (local_taken != global_taken)
                    selector[idx] <= update_counter(selector[idx],global_taken == actual_taken);
                local_history[idx] <= {local_history[idx][0],actual_taken};
                global_history <= {global_history[0],actual_taken};
            end
            if ((update_kind == 0 && actual_taken) || update_kind == 1) begin
                btb_valid[idx] <= 1; btb_tag[idx] <= pc; btb_value[idx] <= actual_target;
            end
            if (update_kind == 1) begin
                if (stack_count < 4) begin stack[stack_count] <= pc + 4; stack_count <= stack_count + 1'b1; end
                else begin
                    stack[0] <= stack[1]; stack[1] <= stack[2]; stack[2] <= stack[3]; stack[3] <= pc + 4;
                end
            end else if (update_kind == 2 && stack_count != 0) stack_count <= stack_count - 1'b1;
        end
    end
endmodule
