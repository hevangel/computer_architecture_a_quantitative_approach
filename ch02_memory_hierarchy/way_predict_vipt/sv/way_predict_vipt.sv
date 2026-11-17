// Two-way VIPT teaching cache, write-through and critical-word-first refill.
module way_predict_vipt #(parameter integer PAGE_BITS=12)(
 input logic clk,reset,req_valid,req_write,
 input logic [15:0] req_vaddr,req_paddr,
 input logic [31:0] req_wdata,
 output logic req_ready,resp_valid,resp_fault,
 output logic [31:0] resp_data,
 output logic config_safe,refill_busy,
 output logic [1:0] refill_word,
 output logic [31:0] stat_fast,stat_slow,stat_miss,stat_way_reads,
 input logic [15:0] dbg_paddr,output logic [31:0] dbg_memory
);
 localparam [1:0] IDLE=0,PROBE=1,FILL=2;
 localparam integer OFFSET_BITS=4,INDEX_BITS=2;
 localparam [15:0] PAGE_MASK=16'hffff >> (16-PAGE_BITS);
 logic [1:0] state; logic valid[0:7],predict[0:3]; logic [9:0] tag[0:7];
 logic [31:0] cache[0:31],memory[0:16383];
 logic [15:0] address_q; logic write_q; logic [31:0] data_q; logic [1:0] set_q,off_q,beat;
 logic target_q; integer entry; logic [1:0] next_word; logic [13:0] memory_word;
 initial if(PAGE_BITS<1 || PAGE_BITS>16) $fatal(1,"PAGE_BITS out of range");
 assign config_safe=(OFFSET_BITS+INDEX_BITS<=PAGE_BITS);
 assign req_ready=(state==IDLE); assign refill_busy=(state==FILL);
 assign refill_word=off_q+beat;
 assign dbg_memory=memory[dbg_paddr[15:2]];
 always_ff @(posedge clk) begin
  if(reset) begin
   state<=IDLE; resp_valid<=0; resp_fault<=0; resp_data<=0; beat<=0;
   stat_fast<=0; stat_slow<=0; stat_miss<=0; stat_way_reads<=0;
   for(integer i=0;i<8;i=i+1) begin valid[i]<=0; tag[i]<=0; end
   for(integer i=0;i<4;i=i+1) predict[i]<=0;
   for(integer i=0;i<32;i=i+1) cache[i]<=0;
   for(integer i=0;i<16384;i=i+1) memory[i]<=32'h10000000+32'(i);
  end else begin
   resp_valid<=0; resp_fault<=0;
   case(state)
    IDLE: if(req_valid) begin
     if(!config_safe || ((req_vaddr & PAGE_MASK)!=(req_paddr & PAGE_MASK)) || req_vaddr[1:0]!=0) begin
      resp_valid<=1; resp_fault<=1; resp_data<=0;
     end else begin
      entry=int'(req_vaddr[5:4])*2+int'(predict[req_vaddr[5:4]]);
      stat_way_reads<=stat_way_reads+1;
      if(valid[entry] && tag[entry]==req_paddr[15:6]) begin
       stat_fast<=stat_fast+1; resp_valid<=1;
       if(req_write) begin cache[entry*4+int'(req_vaddr[3:2])]<=req_wdata; memory[req_paddr[15:2]]<=req_wdata; resp_data<=req_wdata; end
       else resp_data<=cache[entry*4+int'(req_vaddr[3:2])];
      end else begin
       address_q<=req_paddr; set_q<=req_vaddr[5:4]; off_q<=req_vaddr[3:2]; write_q<=req_write; data_q<=req_wdata; state<=PROBE;
      end
     end
    end
    PROBE: begin
     entry=int'(set_q)*2+int'(!predict[set_q]); stat_way_reads<=stat_way_reads+1;
     if(valid[entry] && tag[entry]==address_q[15:6]) begin
      stat_slow<=stat_slow+1; predict[set_q]<=!predict[set_q]; resp_valid<=1; state<=IDLE;
      if(write_q) begin cache[entry*4+int'(off_q)]<=data_q; memory[address_q[15:2]]<=data_q; resp_data<=data_q; end
      else resp_data<=cache[entry*4+int'(off_q)];
     end else begin
      stat_miss<=stat_miss+1;
      if(!valid[int'(set_q)*2]) target_q<=0;
      else if(!valid[int'(set_q)*2+1]) target_q<=1;
      else target_q<=!predict[set_q];
      beat<=0; state<=FILL;
     end
    end
    FILL: begin
     next_word=off_q+beat; entry=int'(set_q)*2+int'(target_q);
     memory_word={address_q[15:4],next_word};
     if(beat==0) begin
      resp_valid<=1;
      if(write_q) begin cache[entry*4+int'(next_word)]<=data_q; memory[memory_word]<=data_q; resp_data<=data_q; end
      else begin cache[entry*4+int'(next_word)]<=memory[memory_word]; resp_data<=memory[memory_word]; end
     end else cache[entry*4+int'(next_word)]<=memory[memory_word];
     if(beat==3) begin valid[entry]<=1; tag[entry]<=address_q[15:6]; predict[set_q]<=target_q; state<=IDLE; end
     else beat<=beat+1;
    end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
