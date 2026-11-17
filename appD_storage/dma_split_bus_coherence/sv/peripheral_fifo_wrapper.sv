// Four-entry peripheral FIFOs wrap the split-bus DMA core.
module dma_split_bus_coherence (
  input logic clk, reset, cpu_valid, cpu_write,
  input logic [3:0] cpu_addr, input logic [31:0] cpu_wdata,
  output logic cpu_ready, cpu_rvalid, output logic [31:0] cpu_rdata,
  input logic start, direction, snoop, irq_ack,
  input logic [3:0] desc_addr, input logic [4:0] desc_length,
  output logic busy, irq, desc_error,
  input logic periph_in_valid, output logic periph_in_ready, input logic [31:0] periph_in_data,
  output logic periph_out_valid, input logic periph_out_ready, output logic [31:0] periph_out_data
);
  logic [31:0] in_fifo[0:3], out_fifo[0:3];
  logic [1:0] in_rd,in_wr,out_rd,out_wr;
  logic [2:0] in_count,out_count;
  logic core_in_ready,core_out_valid,core_out_ready;
  logic [31:0] core_out_data;
  logic in_push,in_pop,out_push,out_pop;
  assign periph_in_ready=(in_count<4);
  assign periph_out_valid=(out_count!=0);
  assign periph_out_data=out_fifo[out_rd];
  assign core_out_ready=(out_count<4);
  assign in_push=periph_in_valid && periph_in_ready;
  assign in_pop=(in_count!=0) && core_in_ready;
  assign out_push=core_out_valid && core_out_ready;
  assign out_pop=periph_out_valid && periph_out_ready;
  dma_coherence_core core(.clk,.reset,.cpu_valid,.cpu_write,.cpu_addr,.cpu_wdata,.cpu_ready,.cpu_rvalid,.cpu_rdata,
    .start,.direction,.snoop,.irq_ack,.desc_addr,.desc_length,.busy,.irq,.desc_error,
    .periph_in_valid(in_count!=0),.periph_in_ready(core_in_ready),.periph_in_data(in_fifo[in_rd]),
    .periph_out_valid(core_out_valid),.periph_out_ready(core_out_ready),.periph_out_data(core_out_data));
  always_ff @(posedge clk) begin
    if (reset) begin in_rd<=0; in_wr<=0; out_rd<=0; out_wr<=0; in_count<=0; out_count<=0; end
    else begin
      if (in_push) begin in_fifo[in_wr]<=periph_in_data; in_wr<=in_wr+1; end
      if (in_pop) in_rd<=in_rd+1;
      case ({in_push,in_pop}) 2'b10:in_count<=in_count+1; 2'b01:in_count<=in_count-1; default:; endcase
      if (out_push) begin out_fifo[out_wr]<=core_out_data; out_wr<=out_wr+1; end
      if (out_pop) out_rd<=out_rd+1;
      case ({out_push,out_pop}) 2'b10:out_count<=out_count+1; 2'b01:out_count<=out_count-1; default:; endcase
    end
  end
endmodule
