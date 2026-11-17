// Four data bytes + P/Q and eight data nibbles + two symbol checks.
module raid6_p_q_chipkill (
    input logic [31:0] data_in,
    output logic [47:0] encoded,
    input logic [47:0] stripe_in,
    input logic [5:0] erased,
    output logic [47:0] recovered,
    output logic recover_valid,
    input logic [31:0] symbols_in,
    output logic [39:0] symbol_encoded,
    input logic [39:0] symbol_received,
    output logic [39:0] symbol_corrected,
    output logic symbol_valid,
    output logic [3:0] symbol_error_position
);
  function automatic [7:0] mul8(input [7:0] a, b);
    reg [7:0] x, y, z;
    begin
      x=a; y=b; z=0;
      for (integer i=0;i<8;i=i+1) begin
        if (y[0]) z=z^x;
        if (x[7]) x=(x<<1)^8'h1d; else x=x<<1;
        y=y>>1;
      end
      mul8=z;
    end
  endfunction
  function automatic [7:0] div8(input [7:0] a,b);
    reg [7:0] x, y;
    begin
      x=1; y=b;
      // b^254 is the inverse in GF(256).
      for (integer i=0;i<8;i=i+1) begin
        if ((254 >> i) & 1) x=mul8(x,y);
        y=mul8(y,y);
      end
      div8=mul8(a,x);
    end
  endfunction
  function automatic [3:0] mul4(input [3:0] a,b);
    reg [3:0] x,y,z;
    begin
      x=a; y=b; z=0;
      for (integer i=0;i<4;i=i+1) begin
        if (y[0]) z=z^x;
        if (x[3]) x=(x<<1)^4'h3; else x=x<<1;
        y=y>>1;
      end
      mul4=z;
    end
  endfunction
  function automatic [7:0] coeff8(input integer i);
    begin case(i) 0:coeff8=1; 1:coeff8=2; 2:coeff8=4; default:coeff8=8; endcase end
  endfunction
  always_comb begin : logic_block
    reg [7:0] p,q,pr,qr,x,coef;
    reg [31:0] d;
    reg [3:0] sp,sq,cp,cq,c4,sym;
    reg [39:0] corr;
    integer count, first, second, nd;
    reg found;
    p=0; q=0;
    for (integer i=0;i<4;i=i+1) begin
      p=p^data_in[i*8+:8]; q=q^mul8(data_in[i*8+:8],coeff8(i));
    end
    encoded={q,p,data_in};
    count=0; first=0; second=0; nd=0;
    for (integer i=0;i<6;i=i+1) if (erased[i]) count=count+1;
    d=stripe_in[31:0]; pr=0; qr=0;
    if (!erased[4]) pr=stripe_in[39:32];
    if (!erased[5]) qr=stripe_in[47:40];
    for (integer i=0;i<4;i=i+1) begin
      if (erased[i]) begin
        if (nd==0) first=i; else second=i;
        nd=nd+1;
      end else begin
        pr=pr^stripe_in[i*8+:8];
        qr=qr^mul8(stripe_in[i*8+:8],coeff8(i));
      end
    end
    x=0; coef=0;
    if (count<=2 && nd==1) begin
      if (!erased[4]) x=pr; else x=div8(qr,coeff8(first));
      d[first*8+:8]=x;
    end else if (count<=2 && nd==2) begin
      coef=coeff8(first)^coeff8(second);
      x=div8(qr^mul8(coeff8(second),pr),coef);
      d[first*8+:8]=x; d[second*8+:8]=pr^x;
    end
    p=0; q=0;
    for (integer i=0;i<4;i=i+1) begin
      p=p^d[i*8+:8]; q=q^mul8(d[i*8+:8],coeff8(i));
    end
    recovered={q,p,d}; recover_valid=(count<=2);
    cp=0; cq=0; c4=1;
    for (integer i=0;i<8;i=i+1) begin
      cp=cp^symbols_in[i*4+:4]; cq=cq^mul4(symbols_in[i*4+:4],c4); c4=mul4(c4,2);
    end
    symbol_encoded={cq,cp,symbols_in};
    cp=0; cq=0; c4=1;
    for (integer i=0;i<8;i=i+1) begin
      cp=cp^symbol_received[i*4+:4]; cq=cq^mul4(symbol_received[i*4+:4],c4); c4=mul4(c4,2);
    end
    sp=cp^symbol_received[35:32]; sq=cq^symbol_received[39:36];
    corr=symbol_received; symbol_valid=1; symbol_error_position=15; found=0; c4=1; sym=0;
    if (sp==0 && sq==0) begin end
    else if (sq==0) begin corr[35:32]=corr[35:32]^sp; symbol_error_position=8; end
    else if (sp==0) begin corr[39:36]=corr[39:36]^sq; symbol_error_position=9; end
    else begin
      for (integer i=0;i<8;i=i+1) begin
        if (!found && mul4(sp,c4)==sq) begin
          sym=corr[i*4+:4]^sp; corr[i*4+:4]=sym;
          symbol_error_position=4'(i); found=1;
        end
        c4=mul4(c4,2);
      end
      if (!found) symbol_valid=0;
    end
    symbol_corrected=corr;
  end
endmodule
