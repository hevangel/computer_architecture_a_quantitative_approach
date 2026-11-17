`timescale 1ns/1ps
module tb_simd_pack_shuffle;
    logic [255:0] words_in;
    logic [63:0] bytes_in;
    logic [127:0] halfwords_in;
    logic signed_extend;
    logic [23:0] byte_select;
    logic [7:0] half_select;
    logic [511:0] tile_in;
    wire [127:0] packed16, extended_bytes;
    wire [63:0] packed8, shuffled_bytes, shuffled_halfwords;
    wire [255:0] extended_halfwords;
    wire [511:0] tile_transposed;
    integer fd, rc, i, row, col, value, e16, e8;
    integer expect16 [0:7], expect8 [0:7];
    logic [15:0] expected_half;
    logic [7:0] expected_byte;
    simd_pack_shuffle dut(words_in,bytes_in,halfwords_in,signed_extend,byte_select,half_select,tile_in,
                           packed16,packed8,extended_bytes,extended_halfwords,shuffled_bytes,shuffled_halfwords,tile_transposed);
    initial begin
        words_in=0; bytes_in=0; halfwords_in=0; byte_select=0; half_select=0; tile_in=0; signed_extend=0;
        fd=$fopen("../../../../ch04_dlp/simd_pack_shuffle/golden.txt","r");
        if (!fd) $fatal(1,"TEST FAILED: missing golden vectors");
        for (i=0;i<8;i=i+1) begin
            rc=$fscanf(fd,"%d %d %d\n",value,e16,e8);
            if (rc!=3) $fatal(1,"TEST FAILED: malformed golden vectors");
            words_in[i*32 +: 32]=value; expect16[i]=e16; expect8[i]=e8;
            bytes_in[i*8 +: 8]=(i*37+128) & 255;
            halfwords_in[i*16 +: 16]=(i*9001+32768) & 65535;
            byte_select[i*3 +: 3]=7-i;
        end
        $fclose(fd);
        for (i=0;i<4;i=i+1) half_select[i*2 +: 2]=3-i;
        for (row=0;row<8;row=row+1)
            for (col=0;col<8;col=col+1) tile_in[(row*8+col)*8 +: 8]=row*8+col;
        #1;
        for (i=0;i<8;i=i+1) begin
            expected_half=expect16[i]; expected_byte=expect8[i];
            if (packed16[i*16 +: 16]!==expected_half || packed8[i*8 +: 8]!==expected_byte ||
                extended_bytes[i*16 +: 16]!=={8'b0,bytes_in[i*8 +: 8]} ||
                extended_halfwords[i*32 +: 32]!=={16'b0,halfwords_in[i*16 +: 16]} ||
                shuffled_bytes[i*8 +: 8]!==bytes_in[(7-i)*8 +: 8])
                $fatal(1,"TEST FAILED: narrowing, zero extension or byte shuffle lane %0d",i);
        end
        for (i=0;i<4;i=i+1)
            if (shuffled_halfwords[i*16 +: 16]!==halfwords_in[(3-i)*16 +: 16]) $fatal(1,"TEST FAILED: halfword shuffle");
        for (row=0;row<8;row=row+1)
            for (col=0;col<8;col=col+1) begin
                expected_byte=row*8+col;
                if (tile_transposed[(col*8+row)*8 +: 8]!==expected_byte) $fatal(1,"TEST FAILED: transpose");
            end
        signed_extend=1; byte_select=0; half_select=0; #1;
        for (i=0;i<8;i=i+1)
            if (extended_bytes[i*16 +: 16]!=={{8{bytes_in[i*8+7]}},bytes_in[i*8 +: 8]} ||
                extended_halfwords[i*32 +: 32]!=={{16{halfwords_in[i*16+15]}},halfwords_in[i*16 +: 16]} ||
                shuffled_bytes[i*8 +: 8]!==bytes_in[7:0]) $fatal(1,"TEST FAILED: sign extension or broadcast");
        for (i=0;i<4;i=i+1)
            if (shuffled_halfwords[i*16 +: 16]!==halfwords_in[15:0]) $fatal(1,"TEST FAILED: halfword broadcast");
        $display("TEST PASSED"); $finish;
    end
endmodule
