// Exact fixed-point reference datapath. One enormous combinational operation;
// this educational implementation is not an optimized production FPU.
module ieee754_fpu_fma_bf16(
    input logic [1:0] op,       // 0 add, 1 multiply, 2 FMA
    input logic [1:0] format,   // 0 binary32, 1 BF16, 2 E5M2, 3 E4M3FN (FMA only)
    input logic [1:0] rounding, // RNE, RTZ, RUP, RDN
    input logic [31:0] a, b, c,
    input logic signed [7:0] scale_a, scale_b,
    output logic [31:0] result,
    output logic [4:0] flags    // NV DZ OF UF NX
);
    localparam integer WIDTH=1112, BIAS=554;
    logic [31:0] ax,bx,cx;
    logic sa,sb,sc, sign1,sign2,signout, zero_sign;
    logic nana,nanb,nanc,snana,snanb,snanc,infa,infb,infc,za,zb,zc;
    logic invalid, anynan, inf1, inf2, add_second;
    logic [23:0] ma,mb,mc;
    logic [47:0] product;
    logic [WIDTH-1:0] term1,term2,mag;
    logic [24:0] q;
    logic guard_bit,sticky_bit,inexact,increment,to_inf;
    integer ea,eb,ec,shift1,shift2,hi,exponent,shift_out,j;
    logic [7:0] out_exp;

    function automatic [31:0] expand(input [31:0] inbits, input [1:0] fmt);
        integer e,f,base,m,h,k,ee;
        reg signbit;
        reg [31:0] tmp;
        begin
            if (fmt==0) expand=inbits;
            else if (fmt==1) expand={inbits[15:0],16'b0};
            else begin
                signbit=inbits[7];
                if (fmt==2) begin
                    e=(inbits>>2)&31; f=inbits&3;
                    if (e==31) tmp=({31'b0,signbit}<<31)|32'h7f800000|(f<<21);
                    else begin
                        if (e==0) begin m=f; base=-16; end
                        else begin m=4+f; base=e-17; end
                        tmp=0;
                        if (m!=0) begin
                            h=0; for(k=0;k<4;k=k+1) if ((m>>k)&1) h=k;
                            ee=base+h+127; tmp=(ee<<23)|((m<<(23-h))&32'h7fffff);
                        end
                        tmp=tmp|({31'b0,signbit}<<31);
                    end
                end else begin
                    e=(inbits>>3)&15; f=inbits&7;
                    if (e==15 && f==7) tmp=({31'b0,signbit}<<31)|32'h7fc00000;
                    else begin
                        if (e==0) begin m=f; base=-9; end
                        else begin m=8+f; base=e-10; end
                        tmp=0;
                        if (m!=0) begin
                            h=0; for(k=0;k<4;k=k+1) if ((m>>k)&1) h=k;
                            ee=base+h+127; tmp=(ee<<23)|((m<<(23-h))&32'h7fffff);
                        end
                        tmp=tmp|({31'b0,signbit}<<31);
                    end
                end
                expand=tmp;
            end
        end
    endfunction

    always @* begin
        ax=expand(a,op==2 ? format : 0); bx=expand(b,op==2 ? format : 0); cx=c;
        sa=ax[31]; sb=bx[31]; sc=cx[31];
        nana=(&ax[30:23]) && (|ax[22:0]); nanb=(&bx[30:23]) && (|bx[22:0]);
        nanc=(&cx[30:23]) && (|cx[22:0]);
        snana=nana && !ax[22]; snanb=nanb && !bx[22]; snanc=nanc && !cx[22];
        infa=(&ax[30:23]) && !(|ax[22:0]); infb=(&bx[30:23]) && !(|bx[22:0]);
        infc=(&cx[30:23]) && !(|cx[22:0]);
        za=!(|ax[30:0]); zb=!(|bx[30:0]); zc=!(|cx[30:0]);
        ma={ax[30:23]!=0,ax[22:0]}; mb={bx[30:23]!=0,bx[22:0]}; mc={cx[30:23]!=0,cx[22:0]};
        ea=(ax[30:23]==0) ? -149 : $signed({1'b0,ax[30:23]})-150;
        eb=(bx[30:23]==0) ? -149 : $signed({1'b0,bx[30:23]})-150;
        ec=(cx[30:23]==0) ? -149 : $signed({1'b0,cx[30:23]})-150;
        if (op==2 && format!=0) begin ea=ea+$signed(scale_a); eb=eb+$signed(scale_b); end
        product=ma*mb;
        term1=0; term2=0; mag=0; sign1=0; sign2=0;
        shift1=0; shift2=0;
        add_second=(op!=1);
        if (op==0) begin
            term1=ma; shift1=ea+BIAS; term2=mb; shift2=eb+BIAS; sign1=sa; sign2=sb;
        end else begin
            term1=product; shift1=ea+eb+BIAS; term2=mc; shift2=ec+BIAS; sign1=sa^sb; sign2=sc;
        end
        term1=term1<<shift1; term2=term2<<shift2;
        inf1=(op==0) ? infa : (infa||infb);
        inf2=(op==0) ? infb : infc;
        invalid=0;
        if (op!=0 && ((infa&&zb)||(infb&&za))) invalid=1;
        if (add_second && inf1 && inf2 && sign1!=sign2 && !(nana||nanb||(op==2&&nanc))) invalid=1;
        anynan=nana||nanb||(op==2&&nanc);
        if (snana||snanb||(op==2&&snanc)) invalid=1;
        result=0; flags=0; signout=0; zero_sign=0; hi=-1; exponent=0; shift_out=0;
        q=0; guard_bit=0; sticky_bit=0; inexact=0; increment=0; to_inf=0; out_exp=0;
        if (anynan || invalid) begin
            result=32'h7fc00000; flags[4]=invalid;
        end else if (inf1 || (add_second&&inf2)) begin
            if (inf1) result={sign1,8'hff,23'b0};
            else result={sign2,8'hff,23'b0};
        end else begin
            if (!add_second) begin mag=term1; signout=sign1; end
            else if (sign1==sign2) begin mag=term1+term2; signout=sign1; end
            else if (term1>term2) begin mag=term1-term2; signout=sign1; end
            else if (term2>term1) begin mag=term2-term1; signout=sign2; end
            else begin mag=0; signout=(rounding==3); end
            if (mag==0) begin
                if (!add_second) zero_sign=sign1;
                else if (term1==0 && term2==0 && sign1==sign2) zero_sign=sign1;
                else zero_sign=(rounding==3);
                result={zero_sign,31'b0};
            end else begin
                for (j=0;j<WIDTH;j=j+1) if (mag[j]) hi=j;
                exponent=hi-BIAS;
                if (exponent < -126) shift_out=BIAS-149;
                else shift_out=hi-23;
                q=mag>>shift_out;
                if (shift_out>0) begin
                    guard_bit=mag[shift_out-1];
                    for (j=0;j<WIDTH;j=j+1) if (j<shift_out-1 && mag[j]) sticky_bit=1;
                end
                inexact=guard_bit||sticky_bit;
                case(rounding)
                    0: increment=guard_bit&&(sticky_bit||q[0]);
                    1: increment=0;
                    2: increment=inexact&&!signout;
                    3: increment=inexact&&signout;
                endcase
                q=q+increment;
                if (exponent>=-126 && q[24]) begin q=q>>1; exponent=exponent+1; end
                if (exponent>127) begin
                    to_inf=(rounding==0)||(rounding==2&&!signout)||(rounding==3&&signout);
                    result={signout,(to_inf ? 31'h7f800000 : 31'h7f7fffff)};
                    flags=5'b00101;
                end else if (exponent < -126) begin
                    if (q[23]) begin result={signout,8'h01,23'b0}; flags[0]=inexact; end
                    else begin result={signout,8'h00,q[22:0]}; flags[1]=inexact; flags[0]=inexact; end
                end else begin
                    out_exp=exponent+127; result={signout,out_exp,q[22:0]}; flags[0]=inexact;
                end
            end
        end
    end
endmodule
