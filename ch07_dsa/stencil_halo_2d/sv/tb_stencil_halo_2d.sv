`timescale 1ns/1ps
module tb_stencil_halo_2d;
  logic clk=0,reset=1,load_valid=0,start=0,wrap_edges=0,out_ready=0;
  logic [5:0] load_addr=0; logic [7:0] load_data=0; logic [1:0] filter_mode=0,shift_direction=0,out_tile;
  logic busy,out_valid; logic [255:0] out_values; logic [6:0] load_count; logic [7:0] scratch_read_count;
  logic [255:0] expected; integer fd,rc;
  always #5 clk=~clk;
  stencil_halo_2d dut(.*);
  initial begin
    fd=$fopen("../../../../ch07_dsa/stencil_halo_2d/golden.txt","r"); if(fd==0) $fatal(1,"missing vectors");
    repeat(2) @(negedge clk); reset=0;
    for(integer y=0;y<8;y=y+1) for(integer x=0;x<8;x=x+1) begin
      load_valid=1; load_addr=6'(y*8+x); load_data=8'((y*37+x*19+y*x*3)%256); @(negedge clk);
    end
    load_valid=0; if(load_count!=64) $fatal(1,"load count");
    for(integer wrap=0;wrap<2;wrap=wrap+1) for(integer mode=0;mode<3;mode=mode+1) begin
      wrap_edges=1'(wrap); filter_mode=2'(mode); start=1; @(negedge clk); start=0;
      for(integer tile=0;tile<4;tile=tile+1) begin
        rc=$fscanf(fd,"%h\n",expected); if(rc!=1) $fatal(1,"short vectors");
        begin : await_tile
          integer waited; waited=0;
          while(!out_valid && waited<50) begin @(negedge clk); waited=waited+1; end
          if(!out_valid || out_tile!==2'(tile) || out_values!==expected) $fatal(1,"stencil mismatch w=%0d m=%0d t=%0d",wrap,mode,tile);
          if(scratch_read_count!==(tile<2?8'(36+24*tile):8'(96+24*(tile-2)))) $fatal(1,"read count for tile %0d",tile);
        end
        load_valid=1; load_addr=0; load_data=255; // input writes must be ignored while busy
        repeat(2) begin @(negedge clk); if(!out_valid || out_tile!==2'(tile) || out_values!==expected) $fatal(1,"stall mismatch"); end
        load_valid=0; out_ready=1; @(negedge clk); out_ready=0;
      end
      if(busy || load_count!=64 || scratch_read_count!=120) $fatal(1,"completion or fetch count");
    end
    for(integer wrap=0;wrap<2;wrap=wrap+1) for(integer dir=0;dir<4;dir=dir+1) begin
      wrap_edges=1'(wrap); filter_mode=3; shift_direction=2'(dir); start=1; @(negedge clk); start=0;
      for(integer t=0;t<4;t=t+1) begin
        rc=$fscanf(fd,"%h\n",expected); if(rc!=1) $fatal(1,"short shift vectors");
        begin : await_shift
          integer waited; waited=0;
          while(!out_valid && waited<50) begin @(negedge clk); waited=waited+1; end
          if(!out_valid || out_tile!==2'(t) || out_values!==expected) $fatal(1,"shift mismatch w=%0d dir=%0d tile=%0d",wrap,dir,t);
        end
        out_ready=1; @(negedge clk); out_ready=0;
      end
      if(busy || load_count!=64 || scratch_read_count!=120) $fatal(1,"fetch count in shift");
    end
    // Keep ready high during refill; no tile may be consumed before it is valid.
    $rewind(fd); @(negedge clk); wrap_edges=0; filter_mode=0; start=1; out_ready=1;
    @(negedge clk); start=0; load_valid=1; load_addr=0; load_data=255;
    repeat(10) @(negedge clk); load_valid=0;
    for(integer t=0;t<4;t=t+1) begin
      rc=$fscanf(fd,"%h\n",expected); if(rc!=1) $fatal(1,"short ready-high vectors");
      begin : await_always_ready
        integer waited; waited=0;
        while(!out_valid && waited<50) begin @(negedge clk); waited=waited+1; end
        if(!out_valid || out_tile!==2'(t) || out_values!==expected) $fatal(1,"ready-high tile %0d",t);
      end
      @(negedge clk);
    end
    out_ready=0; if(busy || load_count!=64 || scratch_read_count!=120) $fatal(1,"ready-high completion");
    $fclose(fd); $display("TEST PASSED"); $finish;
  end
  initial begin #30000; $fatal(1,"timeout"); end
endmodule
