`timescale 1ns/1ps
module tb_dma_split_bus_coherence;
  logic clk=0, reset=1, cpu_valid=0,cpu_write=0,start=0,direction=0,snoop=0,irq_ack=0;
  logic [3:0] cpu_addr=0,desc_addr=0; logic [4:0] desc_length=0;
  logic [31:0] cpu_wdata=0,cpu_rdata,periph_in_data=0,periph_out_data;
  logic cpu_ready,cpu_rvalid,busy,irq,desc_error,periph_in_valid=0,periph_in_ready,periph_out_valid,periph_out_ready=0;
  always #5 clk=~clk;
  dma_split_bus_coherence dut(.*);
  task automatic cpu_store(input [3:0] a,input [31:0] v);
    begin @(negedge clk); cpu_valid=1; cpu_write=1; cpu_addr=a; cpu_wdata=v;
      while (!cpu_ready) @(negedge clk);
      @(negedge clk); cpu_valid=0; cpu_write=0;
    end
  endtask
  task automatic cpu_load(input [3:0] a,input [31:0] expected);
    begin @(negedge clk); cpu_valid=1; cpu_write=0; cpu_addr=a;
      while (!cpu_ready) @(negedge clk);
      @(negedge clk); if (!cpu_rvalid || cpu_rdata!==expected) $fatal(1,"CPU read addr=%0d got=%h expected=%h",a,cpu_rdata,expected);
      cpu_valid=0;
    end
  endtask
  task automatic launch(input [3:0] a,input [4:0] n,input bit dir,input bit sn);
    begin @(negedge clk); desc_addr=a; desc_length=n; direction=dir; snoop=sn; start=1;
      @(negedge clk); start=0;
    end
  endtask
  task automatic send_word(input [31:0] v);
    begin @(negedge clk); periph_in_data=v; periph_in_valid=1;
      while (!periph_in_ready) @(negedge clk);
      @(negedge clk); periph_in_valid=0;
    end
  endtask
  task automatic receive_word(input [31:0] v);
    begin
      while (!periph_out_valid) @(negedge clk);
      if (periph_out_data!==v) $fatal(1,"DMA output mismatch");
      repeat (2) begin @(negedge clk); if (!periph_out_valid || periph_out_data!==v) $fatal(1,"output changed under backpressure"); end
      periph_out_ready=1; @(negedge clk); periph_out_ready=0;
    end
  endtask
  initial begin
    repeat (2) @(negedge clk); reset=0;
    // Fill input FIFO before starting DMA, then verify it backpressures.
    send_word(201); send_word(202); send_word(203); send_word(204);
    if (periph_in_ready) $fatal(1,"full input FIFO accepted data");
    launch(8,4,0,1); while (!irq) @(negedge clk);
    cpu_load(8,201); cpu_load(9,202); cpu_load(10,203); cpu_load(11,204);
    // Let the output FIFO fill entirely before draining it.
    launch(8,4,1,1); while (!irq) @(negedge clk);
    receive_word(201); receive_word(202); receive_word(203); receive_word(204);
    cpu_store(2,32'h55); cpu_load(2,32'h55);
    launch(2,3,0,0); send_word(11); send_word(22); send_word(33);
    while (!irq) @(negedge clk);
    cpu_load(2,32'h55); // stale cached copy without snooping
    cpu_load(3,22); cpu_load(2,11); cpu_load(4,33);
    cpu_load(2,11); // cache the target again
    launch(2,3,0,1); send_word(101); send_word(102); send_word(103);
    while (!irq) @(negedge clk);
    cpu_load(2,101); cpu_load(3,102); cpu_load(4,103);
    launch(2,3,1,1); receive_word(101); receive_word(102); receive_word(103);
    while (!irq) @(negedge clk);
    @(negedge clk); irq_ack=1; @(negedge clk); irq_ack=0;
    if (irq) $fatal(1,"IRQ did not clear");
    launch(15,2,0,1); if (!desc_error || busy) $fatal(1,"invalid descriptor accepted");
    launch(15,31,0,1); if (!desc_error || busy) $fatal(1,"overflowing descriptor accepted");
    launch(0,0,0,1); if (!desc_error || busy) $fatal(1,"zero descriptor accepted");
    $display("TEST PASSED"); $finish;
  end
  initial begin #20000; $fatal(1,"timeout"); end
endmodule
