module omega8 (
    input logic clk, reset,
    input logic [7:0] in_valid, in_tail,
    output logic [7:0] in_ready,
    input logic [23:0] in_dest,
    input logic [127:0] in_data,
    output logic [7:0] out_valid, out_tail,
    input logic [7:0] out_ready,
    output logic [127:0] out_data
);
    logic [23:0] full, next_full;
    logic [2:0] dest [0:23], next_dest [0:23];
    logic [15:0] data [0:23], next_data [0:23];
    logic [23:0] tail, next_tail;
    // Each output owns a reservation from its header until its tail.
    logic [23:0] reserved, next_reserved, side, next_side, rr, next_rr;

    function automatic integer shuffle(input integer wire_id);
        shuffle=((wire_id<<1)&7)|(wire_id>>2);
    endfunction

    always @* begin : route
        integer stage, port_id, slot, downstream, first, candidate, selected, option_id, i;
        logic credit;
        next_full=full; next_tail=tail; next_reserved=reserved; next_side=side; next_rr=rr;
        out_data=0; out_tail=0; out_valid=0;
        in_ready=~full[7:0] & {8{!reset}};
        for (i=0;i<24;i=i+1) begin next_dest[i]=dest[i]; next_data[i]=data[i]; end
        for (stage=0;stage<3;stage=stage+1) begin
            for (port_id=0;port_id<8;port_id=port_id+1) begin
                slot=8*stage+port_id;
                if (stage==2) begin downstream=0; credit=out_ready[port_id]; end
                else begin
                    downstream=8*(stage+1)+shuffle(port_id);
                    credit=!full[downstream];
                end
                first=8*stage+(port_id&6);
                selected=-1;
                for (option_id=0;option_id<2;option_id=option_id+1) begin
                    if (reserved[slot]) candidate=first+int'(side[slot]);
                    else candidate=first+((int'(rr[slot])+option_id)%2);
                    if (selected<0 && full[candidate] &&
                        dest[candidate][2-stage]==port_id[0]) selected=candidate;
                end
                if (selected>=0) begin
                    if (stage==2) begin
                        out_valid[port_id]=!reset;
                        out_data[16*port_id +: 16]=data[selected];
                        out_tail[port_id]=tail[selected];
                        if (!credit && !reserved[slot]) begin
                            next_reserved[slot]=1; next_side[slot]=selected[0];
                        end
                    end
                    if (credit) begin
                        next_full[selected]=0;
                        next_reserved[slot]=!tail[selected];
                        next_side[slot]=selected[0];
                        if (tail[selected]) next_rr[slot]=!selected[0];
                        if (stage!=2) begin
                            next_full[downstream]=1;
                            next_dest[downstream]=dest[selected];
                            next_data[downstream]=data[selected];
                            next_tail[downstream]=tail[selected];
                        end
                    end
                end
            end
        end
        for (i=0;i<8;i=i+1) begin
            if (in_valid[i] && in_ready[i]) begin
                next_full[i]=1;
                next_dest[i]=in_dest[3*i +: 3];
                next_data[i]=in_data[16*i +: 16];
                next_tail[i]=in_tail[i];
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            full<=0; tail<=0; reserved<=0; side<=0; rr<=0;
            for (integer i=0;i<24;i=i+1) begin dest[i]<=0; data[i]<=0; end
        end else begin
            full<=next_full; tail<=next_tail; reserved<=next_reserved; side<=next_side; rr<=next_rr;
            for (integer i=0;i<24;i=i+1) begin dest[i]<=next_dest[i]; data[i]<=next_data[i]; end
        end
    end
endmodule

module islip8 #(parameter integer ITERATIONS=4)(
    input logic clk, reset, advance,
    input logic [63:0] requests,
    output logic [63:0] connections
);
    integer grant_pointer [0:7], accept_pointer [0:7];
    integer next_grant [0:7], next_accept [0:7];
    always @* begin : arbitrate
        logic [7:0] matched_in, matched_out;
        integer granted_by [0:7];
        integer i, o, offset, candidate, accepted, iteration;
        connections=0; matched_in=0; matched_out=0;
        for (i=0;i<8;i=i+1) begin
            next_grant[i]=grant_pointer[i]; next_accept[i]=accept_pointer[i];
        end
        for (iteration=0;iteration<ITERATIONS;iteration=iteration+1) begin
            for (o=0;o<8;o=o+1) begin
                granted_by[o]=-1;
                for (offset=0;offset<8;offset=offset+1) begin
                    candidate=(grant_pointer[o]+offset)%8;
                    if (!matched_out[o] && !matched_in[candidate] &&
                        requests[8*candidate+o] && granted_by[o]<0)
                        granted_by[o]=candidate;
                end
            end
            for (i=0;i<8;i=i+1) begin
                accepted=-1;
                for (offset=0;offset<8;offset=offset+1) begin
                    candidate=(accept_pointer[i]+offset)%8;
                    if (granted_by[candidate]==i && accepted<0) accepted=candidate;
                end
                if (accepted>=0) begin
                    connections[8*i+accepted]=1; matched_in[i]=1; matched_out[accepted]=1;
                    if (iteration==0) begin
                        next_grant[accepted]=(i+1)%8;
                        next_accept[i]=(accepted+1)%8;
                    end
                end
            end
        end
    end
    always @(posedge clk) begin
        for (integer i=0;i<8;i=i+1) begin
            if (reset) begin grant_pointer[i]<=0; accept_pointer[i]<=0; end
            else if (advance) begin grant_pointer[i]<=next_grant[i]; accept_pointer[i]<=next_accept[i]; end
        end
    end
endmodule
