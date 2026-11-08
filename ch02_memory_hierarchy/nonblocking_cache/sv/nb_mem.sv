// Main memory model for nb_cache: one request per cycle, in order, with occupancy and a fixed read latency.
//   * a request is accepted in a cycle with mem_ready = 1; a write keeps the port busy for WR_OCC cycles (including the accepting cycle), a read for RD_OCC;
//   * a write takes effect at once (functionally); a read samples the line at acceptance and returns it MEM_LAT cycles later (mem_rvalid in cycle accept + MEM_LAT)
//     together with the tag it was issued with.
// `violation` is raised if the cache ever presents a request while mem_ready is low.
module nb_mem #(parameter int MEM_LAT = 10, parameter int WR_OCC = 4, parameter int RD_OCC = 1) (
    input  logic clk, rst_n,
    input  logic mem_valid, mem_write,
    input  logic [7:0]  mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic [1:0]  mem_tag,
    output logic mem_ready,
    output logic mem_rvalid,
    output logic [1:0]   mem_rtag,
    output logic [127:0] mem_rline,
    input  logic [7:0]  dbg_addr,
    output logic [31:0] dbg_data,
    output logic violation
);
  logic [31:0] arr [0:255];
  logic [3:0]  busy;
  logic        sv_v [0:15];  logic [1:0] sv_tag [0:15];  logic [127:0] sv_line [0:15];
  assign mem_ready  = (busy == 4'd0);
  assign mem_rvalid = sv_v[MEM_LAT-1];
  assign mem_rtag   = sv_tag[MEM_LAT-1];
  assign mem_rline  = sv_line[MEM_LAT-1];
  assign dbg_data   = arr[dbg_addr];
  logic [7:0] base;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= '0;  violation <= 1'b0;
      for (int i = 0; i < 16; i++) sv_v[i] <= 1'b0;
      for (int a = 0; a < 256; a++) arr[a] <= 32'h5A000000 + 32'(a) * 32'd17;       // distinct initial contents
    end else begin
      for (int i = 1; i < 16; i++) begin sv_v[i] <= sv_v[i-1];  sv_tag[i] <= sv_tag[i-1];  sv_line[i] <= sv_line[i-1]; end
      sv_v[0] <= 1'b0;
      if (busy != 4'd0) busy <= busy - 4'd1;
      if (mem_valid) begin
        if (!mem_ready) violation <= 1'b1;
        else if (mem_write) begin arr[mem_addr] <= mem_wdata;  busy <= 4'(WR_OCC - 1); end
        else begin
          base = {mem_addr[7:2], 2'b00};
          sv_v[0] <= 1'b1;  sv_tag[0] <= mem_tag;
          sv_line[0] <= {arr[base + 8'd3], arr[base + 8'd2], arr[base + 8'd1], arr[base]};
          busy <= 4'(RD_OCC - 1);
        end
      end
    end
  end
endmodule
