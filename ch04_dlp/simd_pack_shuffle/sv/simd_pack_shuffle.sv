// Eight signed 32->16->8 saturating lanes, signed/zero extension, two
// permutation widths, and a fixed 8x8 byte transpose network.
module simd_pack_shuffle (
    input logic [255:0] words_in,
    input logic [63:0] bytes_in,
    input logic [127:0] halfwords_in,
    input logic signed_extend,
    input logic [23:0] byte_select,
    input logic [7:0] half_select,
    input logic [511:0] tile_in,
    output logic [127:0] packed16,
    output logic [63:0] packed8,
    output logic [127:0] extended_bytes,
    output logic [255:0] extended_halfwords,
    output logic [63:0] shuffled_bytes, shuffled_halfwords,
    output logic [511:0] tile_transposed
);
    integer i, row, col;
    logic signed [31:0] word_value;
    logic signed [15:0] half_value;
    always_comb begin
        packed16='0; packed8='0; extended_bytes='0; extended_halfwords='0;
        shuffled_bytes='0; shuffled_halfwords='0; tile_transposed='0;
        word_value=0; half_value=0;
        for (i=0;i<8;i=i+1) begin
            word_value=$signed(words_in[i*32 +: 32]);
            if (word_value > 32767) half_value=16'sh7fff;
            else if (word_value < -32768) half_value=16'sh8000;
            else half_value=word_value[15:0];
            packed16[i*16 +: 16]=half_value;
            if (half_value > 127) packed8[i*8 +: 8]=8'h7f;
            else if (half_value < -128) packed8[i*8 +: 8]=8'h80;
            else packed8[i*8 +: 8]=half_value[7:0];
            extended_bytes[i*16 +: 16]={{8{signed_extend & bytes_in[i*8+7]}},bytes_in[i*8 +: 8]};
            extended_halfwords[i*32 +: 32]={{16{signed_extend & halfwords_in[i*16+15]}},halfwords_in[i*16 +: 16]};
            shuffled_bytes[i*8 +: 8]=bytes_in[byte_select[i*3 +: 3]*8 +: 8];
        end
        for (i=0;i<4;i=i+1)
            shuffled_halfwords[i*16 +: 16]=halfwords_in[half_select[i*2 +: 2]*16 +: 16];
        for (row=0;row<8;row=row+1)
            for (col=0;col<8;col=col+1)
                tile_transposed[(col*8+row)*8 +: 8]=tile_in[(row*8+col)*8 +: 8];
    end
endmodule
