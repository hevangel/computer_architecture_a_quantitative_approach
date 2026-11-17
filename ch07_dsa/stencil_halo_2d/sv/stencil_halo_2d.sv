// Parallel 4x4 stencil over a preloaded 8x8 scratchpad.
module stencil_halo_2d (
  input logic clk,reset,load_valid,
  input logic [5:0] load_addr,
  input logic [7:0] load_data,
  input logic start, wrap_edges,
  input logic [1:0] filter_mode, shift_direction,
  output logic busy,out_valid,
  input logic out_ready,
  output logic [1:0] out_tile,
  output logic [255:0] out_values,
  output logic [6:0] load_count,
  output logic [7:0] scratch_read_count
);
  logic [7:0] mem[0:63];
  logic [7:0] lines[0:5][0:5];
  logic [1:0] tile,mode,shift_latched;
  logic wrap_latched,loading;
  logic [5:0] fill_index;
  function automatic integer sample_pixel(input integer y,x,input logic wrap_mode);
    integer yy,xx;
    begin
      yy=y; xx=x;
      if (wrap_mode) begin
        if (yy<0) yy=yy+8; else if (yy>7) yy=yy-8;
        if (xx<0) xx=xx+8; else if (xx>7) xx=xx-8;
      end else begin
        if (yy<0) yy=0; else if (yy>7) yy=7;
        if (xx<0) xx=0; else if (xx>7) xx=7;
      end
      sample_pixel=int'(mem[yy*8+xx]);
    end
  endfunction
  // Interior lanes exchange north/south/east/west values. Halo edges enter
  // from six buffered rows; the diagonal values are horizontal shifts of N/S.
  always_comb begin : stencil
    integer n,south,east,west,center,nw,ne,sw,se;
    reg signed [15:0] value;
    out_values=0;
    for (integer row=0;row<4;row=row+1) begin
      for (integer col=0;col<4;col=col+1) begin
        center=int'(lines[row+1][col+1]);
        n=int'(lines[row][col+1]); south=int'(lines[row+2][col+1]);
        west=int'(lines[row+1][col]); east=int'(lines[row+1][col+2]);
        nw=int'(lines[row][col]); ne=int'(lines[row][col+2]);
        sw=int'(lines[row+2][col]); se=int'(lines[row+2][col+2]);
        case(mode)
          0:value=(ne+2*east+se)-(nw+2*west+sw);
          1:value=(sw+2*south+se)-(nw+2*n+ne);
          2:value=nw+n+ne+west+center+east+sw+south+se;
          default:case(shift_latched)
            0:value=n; 1:value=south; 2:value=east; 3:value=west;
          endcase
        endcase
        out_values[(row*4+col)*16+:16]=value;
      end
    end
  end
  assign out_valid=busy && !loading; assign out_tile=tile;
  // One scratchpad read per cycle. Even tiles load 36 positions; odd tiles
  // retain two columns from their left neighbor and load the remaining 24.
  always_ff @(posedge clk) begin : sequencer
    integer row,col;
    if (reset) begin
      busy<=0; loading<=0; tile<=0; mode<=0; shift_latched<=0; wrap_latched<=0;
      load_count<=0; scratch_read_count<=0; fill_index<=0;
    end else begin
      if (load_valid && !busy) begin mem[load_addr]<=load_data; load_count<=load_count+1; end
      if (start && !busy) begin
        busy<=1; loading<=1; tile<=0; mode<=filter_mode; shift_latched<=shift_direction;
        wrap_latched<=wrap_edges; fill_index<=0; scratch_read_count<=0;
      end else if (busy && loading) begin
        if(tile[0]) begin row=int'(fill_index)/4; col=int'(fill_index)%4+2; end
        else begin row=int'(fill_index)/6; col=int'(fill_index)%6; end
        lines[row][col]<=8'(sample_pixel((int'(tile)/2)*4+row-1,
                                         (int'(tile)%2)*4+col-1,wrap_latched));
        scratch_read_count<=scratch_read_count+1;
        if ((tile[0] && fill_index==23) || (!tile[0] && fill_index==35)) begin
          loading<=0; fill_index<=0;
        end else fill_index<=fill_index+1;
      end else if (out_valid && out_ready) begin
        if (tile==3) busy<=0;
        else begin
          if (!tile[0]) for (integer r=0;r<6;r=r+1) begin
            lines[r][0]<=lines[r][4]; lines[r][1]<=lines[r][5];
          end
          tile<=tile+1; loading<=1; fill_index<=0;
        end
      end
    end
  end
endmodule
