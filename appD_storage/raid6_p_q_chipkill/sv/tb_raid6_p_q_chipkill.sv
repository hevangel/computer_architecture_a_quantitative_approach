`timescale 1ns/1ps
module tb_raid6_p_q_chipkill;
  logic [31:0] data_in, symbols_in;
  logic [47:0] encoded, stripe_in, recovered;
  logic [5:0] erased;
  logic recover_valid;
  logic [39:0] symbol_encoded, symbol_received, symbol_corrected;
  logic symbol_valid;
  logic [3:0] symbol_error_position;
  logic [47:0] expected_stripe;
  logic [39:0] expected_symbols;
  integer fd, rc, cases, bits;
  raid6_p_q_chipkill dut(.*);
  initial begin
    data_in=0; symbols_in=0; stripe_in=0; erased=0; symbol_received=0; cases=0;
    fd=$fopen("../../../../appD_storage/raid6_p_q_chipkill/golden.txt","r");
    if (fd==0) $fatal(1,"missing golden vectors");
    rc=$fscanf(fd,"%h %h %h\n",data_in,expected_stripe,expected_symbols);
    while (rc==3) begin
      symbols_in=data_in; #1;
      if (encoded!==expected_stripe || symbol_encoded!==expected_symbols) $fatal(1,"encoding mismatch");
      for (integer mask=0; mask<64; mask=mask+1) begin
        bits=0; for (integer i=0;i<6;i=i+1) if ((mask>>i)&1) bits=bits+1;
        erased=6'(mask); stripe_in=expected_stripe;
        for (integer i=0;i<6;i=i+1) if ((mask>>i)&1) stripe_in[i*8+:8]=8'ha5;
        #1;
        if (bits<=2 && (!recover_valid || recovered!==expected_stripe)) $fatal(1,"recovery mismatch mask=%0d",mask);
        if (bits>2 && recover_valid) $fatal(1,"invalid mask accepted");
      end
      symbol_received=expected_symbols; #1;
      if (!symbol_valid || symbol_error_position!==15 || symbol_corrected!==expected_symbols) $fatal(1,"clean symbol mismatch");
      for (integer pos=0;pos<10;pos=pos+1) begin
        for (integer err=1;err<16;err=err+1) begin
          symbol_received=expected_symbols;
          symbol_received[pos*4+:4]=expected_symbols[pos*4+:4]^4'(err);
          #1;
          if (!symbol_valid || symbol_error_position!==4'(pos) || symbol_corrected!==expected_symbols)
            $fatal(1,"symbol mismatch position=%0d error=%0d",pos,err);
        end
      end
      cases=cases+1;
      rc=$fscanf(fd,"%h %h %h\n",data_in,expected_stripe,expected_symbols);
    end
    $fclose(fd);
    if (cases!=36) $fatal(1,"unexpected vector count");
    $display("TEST PASSED %0d vectors",cases); $finish;
  end
endmodule
