// Eight independent single-port banks; 16-lane strips, earliest lane wins.
module vector_bank_gather_strip (
  input logic clk,reset,
  input logic mem_we, input logic [8:0] mem_addr, input logic [31:0] mem_wdata,
  output logic [31:0] mem_rdata,
  input logic vec_we, input logic [5:0] vec_slot, input logic [8:0] vec_index,
  input logic [31:0] vec_wdata, output logic [31:0] vec_result,
  input logic start, indexed, store,
  input logic [6:0] length, input logic [8:0] base, stride,
  output logic busy, done, error,
  output logic [15:0] service_cycles, ideal_cycles, bank_stalls,
  output logic [2:0] strips,
  output logic [4:0] strip_length
);
  logic [31:0] memory[0:511], store_data[0:63], result[0:63];
  logic [8:0] indices[0:63];
  logic [15:0] pending,grants;
  logic [6:0] offset,total;
  logic [8:0] base_latched,stride_latched;
  logic indexed_latched,store_latched;
  logic [8:0] lane_addr[0:15];
  logic [7:0] used;
  function automatic [15:0] mask_for(input [4:0] count);
    if (count==16) mask_for=16'hffff; else mask_for=(16'h0001 << count)-1;
  endfunction
  function automatic [4:0] chunk_for(input [6:0] count);
    if (count>=16) chunk_for=16; else chunk_for=count[4:0];
  endfunction
  assign mem_rdata=memory[mem_addr]; assign vec_result=result[vec_slot];
  assign bank_stalls=service_cycles-ideal_cycles;
  always_comb begin
    used=0; grants=0;
    for(integer lane=0;lane<16;lane=lane+1) begin
      lane_addr[lane]=0;
      if (pending[lane]) begin
        if(indexed_latched) lane_addr[lane]=indices[offset+lane];
        else lane_addr[lane]=base_latched+(offset+lane)*stride_latched;
        if(!used[lane_addr[lane][2:0]]) begin
          used[lane_addr[lane][2:0]]=1; grants[lane]=1;
        end
      end
    end
  end
  always_ff @(posedge clk) begin
    if(reset) begin
      pending<=0; offset<=0; total<=0; busy<=0; done<=0; error<=0;
      base_latched<=0; stride_latched<=0; indexed_latched<=0; store_latched<=0;
      service_cycles<=0; ideal_cycles<=0; strips<=0; strip_length<=0;
    end else begin
      done<=0;
      if(!busy) begin
        if(mem_we) memory[mem_addr]<=mem_wdata;
        if(vec_we) begin indices[vec_slot]<=vec_index; store_data[vec_slot]<=vec_wdata; end
        if(start) begin
          error<=0; service_cycles<=0; ideal_cycles<=0; strips<=0; strip_length<=0; offset<=0;
          if(length>64) begin error<=1; done<=1; end
          else if(length==0) done<=1;
          else begin
            busy<=1; total<=length; indexed_latched<=indexed; store_latched<=store;
            base_latched<=base; stride_latched<=stride;
            strip_length<=chunk_for(length); pending<=mask_for(chunk_for(length));
            ideal_cycles<=(chunk_for(length)+7)>>3; strips<=1;
          end
        end
      end else begin
        service_cycles<=service_cycles+1;
        for(integer lane=0;lane<16;lane=lane+1) if(grants[lane]) begin
          if(store_latched) memory[lane_addr[lane]]<=store_data[offset+lane];
          else result[offset+lane]<=memory[lane_addr[lane]];
        end
        if((pending & ~grants)==0) begin
          if(offset+strip_length>=total) begin busy<=0; done<=1; pending<=0; end
          else begin
            offset<=offset+strip_length;
            strip_length<=chunk_for(total-offset-strip_length);
            pending<=mask_for(chunk_for(total-offset-strip_length));
            ideal_cycles<=ideal_cycles+((chunk_for(total-offset-strip_length)+7)>>3);
            strips<=strips+1;
          end
        end else pending<=pending & ~grants;
      end
    end
  end
endmodule
