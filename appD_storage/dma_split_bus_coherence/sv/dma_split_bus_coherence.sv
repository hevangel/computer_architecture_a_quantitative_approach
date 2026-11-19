// Educational single-outstanding split bus, write-through one-word CPU cache,
// descriptor-driven peripheral-to-memory or memory-to-peripheral DMA.
module dma_coherence_core (
  input logic clk, reset,
  input logic cpu_valid, cpu_write,
  input logic [3:0] cpu_addr,
  input logic [31:0] cpu_wdata,
  output logic cpu_ready, cpu_rvalid,
  output logic [31:0] cpu_rdata,
  input logic start, direction, snoop, irq_ack,
  input logic [3:0] desc_addr,
  input logic [4:0] desc_length,
  output logic busy, irq, desc_error,
  input logic periph_in_valid,
  output logic periph_in_ready,
  input logic [31:0] periph_in_data,
  output logic periph_out_valid,
  input logic periph_out_ready,
  output logic [31:0] periph_out_data
);
  typedef enum logic [2:0] {IDLE, INPUT_WAIT, REQUEST, RESPONSE, OUTPUT_WAIT} state_t;
  state_t state;
  logic [31:0] memory [0:15];
  logic cache_valid;
  logic [3:0] cache_tag, address;
  logic [31:0] cache_data, payload;
  logic [4:0] remaining;
  logic mode, do_snoop;
  logic pending, pending_write;
  logic [3:0] pending_addr;
  logic [31:0] pending_data;
  assign busy = (state != IDLE);
  assign cpu_ready = !pending;
  assign periph_in_ready = (state == INPUT_WAIT);
  assign periph_out_valid = (state == OUTPUT_WAIT);
  assign periph_out_data = payload;
  always_ff @(posedge clk) begin
    if (reset) begin
      state<=IDLE; cache_valid<=0; cache_tag<=0; cache_data<=0;
      address<=0; remaining<=0; mode<=0; do_snoop<=0; payload<=0;
      pending<=0; pending_write<=0; pending_addr<=0; pending_data<=0;
      irq<=0; desc_error<=0; cpu_rvalid<=0; cpu_rdata<=0;
      for (integer i=0;i<16;i=i+1) memory[i]<=0;
    end else begin
      cpu_rvalid<=0;
      if (irq_ack) irq<=0;
      // CPU owns the shared port in a free cycle; writes are write-through.
      if (cpu_valid && cpu_ready) begin
        if (cpu_write) begin
          memory[cpu_addr]<=cpu_wdata;
          if (cache_valid && cache_tag==cpu_addr) cache_data<=cpu_wdata;
        end else begin
          cpu_rvalid<=1;
          if (cache_valid && cache_tag==cpu_addr) cpu_rdata<=cache_data;
          else begin
            cpu_rdata<=memory[cpu_addr]; cache_data<=memory[cpu_addr];
            cache_tag<=cpu_addr; cache_valid<=1;
          end
        end
      end
      // Accepted request responds in the next cycle; no CPU request can race it.
      if (pending) begin
        pending<=0;
        if (pending_write) begin
          memory[pending_addr]<=pending_data;
          if (do_snoop && cache_valid && cache_tag==pending_addr) cache_valid<=0;
        end else payload<=memory[pending_addr];
        if (pending_write) begin
          if (remaining==1) begin state<=IDLE; irq<=1; end
          else begin remaining<=remaining-1; address<=address+1; state<=INPUT_WAIT; end
        end else state<=OUTPUT_WAIT;
      end
      case (state)
        IDLE: if (start) begin
          irq<=0;
          if (desc_length==0 || ({2'b0,desc_addr}+{1'b0,desc_length})>16) desc_error<=1;
          else begin
            desc_error<=0; address<=desc_addr; remaining<=desc_length;
            mode<=direction; do_snoop<=snoop;
            if (direction) state<=REQUEST; else state<=INPUT_WAIT;
          end
        end
        INPUT_WAIT: if (periph_in_valid) begin payload<=periph_in_data; state<=REQUEST; end
        REQUEST: if (!pending && !cpu_valid) begin
          pending<=1; pending_write<=!mode; pending_addr<=address; pending_data<=payload;
          state<=RESPONSE;
        end
        RESPONSE: begin end
        OUTPUT_WAIT: if (periph_out_ready) begin
          if (remaining==1) begin state<=IDLE; irq<=1; end
          else begin remaining<=remaining-1; address<=address+1; state<=REQUEST; end
        end
        default: state<=IDLE;
      endcase
    end
  end
endmodule
