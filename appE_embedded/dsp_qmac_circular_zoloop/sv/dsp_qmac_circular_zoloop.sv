// Q1.15 MAC, convergent rounding, modulo address, bit reversal and repeat counter.
module dsp_qmac_circular_zoloop (
  input logic clk, reset, mac_clear, mac_enable,
  input logic signed [15:0] sample, coefficient,
  output logic signed [39:0] accumulator,
  output logic signed [15:0] rounded_q15,
  input logic pointer_load, pointer_step,
  input logic [3:0] pointer_start,
  input logic [4:0] pointer_modulus,
  output logic [3:0] pointer,
  input logic [3:0] fft_index,
  output logic [3:0] bit_reversed,
  input logic repeat_load, repeat_step,
  input logic [4:0] repeat_count,
  output logic repeat_active, repeat_last
);
  logic signed [31:0] product;
  logic signed [40:0] sum;
  logic signed [39:0] rounded_integer;
  logic [4:0] remaining;
  assign product = sample * coefficient;
  assign sum = {accumulator[39],accumulator} + {{9{product[31]}},product};
  assign bit_reversed = {fft_index[0],fft_index[1],fft_index[2],fft_index[3]};
  assign repeat_active=(remaining!=0);
  assign repeat_last=(remaining==1);
  always_comb begin
    rounded_integer=accumulator >>> 15;
    if (accumulator[14:0]>15'h4000 || (accumulator[14:0]==15'h4000 && rounded_integer[0]))
      rounded_integer=rounded_integer+1;
    if (rounded_integer>40'sd32767) rounded_q15=16'sh7fff;
    else if (rounded_integer< -40'sd32768) rounded_q15=16'sh8000;
    else rounded_q15=rounded_integer[15:0];
  end
  always_ff @(posedge clk) begin
    if (reset) begin accumulator<=0; pointer<=0; remaining<=0; end
    else begin
      if (mac_clear) accumulator<=0;
      else if (mac_enable) begin
        if (sum>41'sh07fffffffff) accumulator<=40'sh7fffffffff;
        else if (sum< -41'sh08000000000) accumulator<=40'sh8000000000;
        else accumulator<=sum[39:0];
      end
      if (pointer_load) pointer<=pointer_start;
      else if (pointer_step && pointer_modulus!=0 && pointer_modulus<=16) begin
        if ({1'b0,pointer}+1>=pointer_modulus) pointer<=0; else pointer<=pointer+1;
      end
      if (repeat_load) remaining<=repeat_count;
      else if (repeat_step && remaining!=0) remaining<=remaining-1;
    end
  end
endmodule
