`timescale 1ns/1ps
module tb_ieee754_fpu_fma_bf16;
    logic [1:0] op,format,rounding;
    logic [31:0] a,b,c;
    logic signed [7:0] scale_a,scale_b;
    wire [31:0] result;
    wire [4:0] flags;
    integer fd,n,ret,op_i,fmt_i,rnd_i,sa_i,sb_i,flag_i;
    logic [31:0] expected;
    ieee754_fpu_fma_bf16 dut(.*);
    initial begin
        fd=$fopen("../../../../appJ_arithmetic/ieee754_fpu_fma_bf16/python/fp_vectors.txt","r");
        if (!fd) $fatal(1,"could not open vector file");
        n=0;
        while (!$feof(fd)) begin
            ret=$fscanf(fd,"%d %d %d %h %h %h %d %d %h %h\n",op_i,fmt_i,rnd_i,a,b,c,sa_i,sb_i,expected,flag_i);
            if (ret==10) begin
                op=op_i; format=fmt_i; rounding=rnd_i; scale_a=sa_i; scale_b=sb_i;
                #1;
                if (result!==expected || flags!==flag_i[4:0])
                    $fatal(1,"vector %0d op %0d fmt %0d rnd %0d a %h b %h c %h scale %0d %0d expected %h/%h got %h/%h",n,op,format,rounding,a,b,c,sa_i,sb_i,expected,flag_i,result,flags);
                n=n+1;
            end else if (ret!=-1) $fatal(1,"invalid vector record %0d",n);
        end
        if (n<5000) $fatal(1,"too few vectors: %0d",n);
        $fclose(fd); $display("TEST PASSED (%0d vectors)",n); $finish;
    end
endmodule
