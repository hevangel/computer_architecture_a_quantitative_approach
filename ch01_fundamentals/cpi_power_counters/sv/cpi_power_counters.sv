module cpi_power_counters #(
    parameter [31:0] DYNAMIC_ENERGY_PER_TOGGLE_Q16 = 32'd65536,
    parameter [31:0] STATIC_ENERGY_PER_CYCLE_Q16 = 32'd16384,
    parameter [31:0] CLOCK_HZ = 32'd1
) (
    input logic clk, reset,
    input logic retire, input logic [1:0] instruction_class,
    input logic stall, input logic [1:0] stall_class,
    input logic activity_enable, input logic [31:0] activity_data,
    output logic [31:0] cycles, retired, stalls, toggles,
    output logic [127:0] retired_by_class, stalls_by_class,
    output logic [47:0] cpi_q16,
    output logic [63:0] dynamic_energy_q16, static_energy_q16, last_power_q16
);
    logic [31:0] last_data;
    logic [5:0] transition_count;
    logic [63:0] dynamic_increment;
    integer bit_index;
    always_comb begin
        transition_count = 0;
        if (activity_enable)
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
                transition_count = transition_count + (activity_data[bit_index] ^ last_data[bit_index]);
        dynamic_increment = {{58{1'b0}}, transition_count} * DYNAMIC_ENERGY_PER_TOGGLE_Q16;
        if (retired == 0) cpi_q16 = 0;
        else cpi_q16 = ({16'b0, cycles} << 16) / retired;
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            cycles <= 0; retired <= 0; stalls <= 0; toggles <= 0;
            retired_by_class <= 0; stalls_by_class <= 0;
            dynamic_energy_q16 <= 0; static_energy_q16 <= 0; last_power_q16 <= 0;
            last_data <= 0;
        end else begin
            cycles <= cycles + 1;
            if (retire) begin
                retired <= retired + 1;
                retired_by_class[instruction_class*32 +: 32] <= retired_by_class[instruction_class*32 +: 32] + 1;
            end
            if (stall) begin
                stalls <= stalls + 1;
                stalls_by_class[stall_class*32 +: 32] <= stalls_by_class[stall_class*32 +: 32] + 1;
            end
            if (activity_enable) last_data <= activity_data;
            toggles <= toggles + transition_count;
            dynamic_energy_q16 <= dynamic_energy_q16 + dynamic_increment;
            static_energy_q16 <= static_energy_q16 + STATIC_ENERGY_PER_CYCLE_Q16;
            last_power_q16 <= (dynamic_increment + STATIC_ENERGY_PER_CYCLE_Q16) * CLOCK_HZ;
        end
    end
endmodule
