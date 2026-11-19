module west_first_adaptive_spec_vc #(
    parameter bit SPECULATIVE=1, ADAPTIVE=1
)(
    input logic clk, reset,
    input logic [15:0] in_valid, out_ready,
    output logic [15:0] in_ready, out_valid,
    input logic [63:0] destination, link_enable,
    input logic [255:0] in_id,
    output logic [255:0] out_id,
    output logic [31:0] link_hops, alternate_turns
);
    localparam integer WEST=0,EAST=1,NORTH=2,SOUTH=3,LOCAL=4;
    logic [159:0] occupied, occupied_next;
    logic [3:0] dest [0:159], dest_next [0:159];
    logic [15:0] packet [0:159], packet_next [0:159];
    // Each output can hold the non-speculative VC allocation for one cycle.
    integer held [0:79], held_next [0:79], target [0:79], target_next [0:79];
    logic held_alt [0:79], held_alt_next [0:79];
    integer local_held [0:15], local_held_next [0:15];
    integer rotation, rotation_next, hops_next, turns_next;
    function automatic integer neighbor(input integer node, direction);
        case (direction)
            WEST:  neighbor=(node%4==0) ? -1 : node-1;
            EAST:  neighbor=(node%4==3) ? -1 : node+1;
            NORTH: neighbor=(node/4==0) ? -1 : node-4;
            SOUTH: neighbor=(node/4==3) ? -1 : node+4;
            default: neighbor=-1;
        endcase
    endfunction

    always @* begin : switch
        integer node,port_id,index,step,n,used_slot,candidate,want,other,chosen,dst,dx,dy,tgt,free1,free2,near1,near2;
        integer vc1,vc2,output_index;
        logic alt;
        logic [79:0] output_busy;
        logic [159:0] input_busy;
        occupied_next=occupied; out_valid=0; out_id=0; in_ready=0;
        output_busy=0; input_busy=0;
        hops_next=link_hops; turns_next=alternate_turns;
        rotation_next=(rotation+1)%10;
        for (index=0;index<160;index=index+1) begin
            dest_next[index]=dest[index]; packet_next[index]=packet[index];
        end
        for (index=0;index<80;index=index+1) begin
            held_next[index]=held[index]; target_next[index]=target[index]; held_alt_next[index]=held_alt[index];
            if (held[index]>=0) begin
                input_busy[held[index]]=1; input_busy[held[index]^1]=1; output_busy[index]=1;
                if (link_enable[4*(index/5)+(index%5)] && !occupied[target[index]]) begin
                    occupied_next[target[index]]=1;
                    dest_next[target[index]]=dest[held[index]]; packet_next[target[index]]=packet[held[index]];
                    occupied_next[held[index]]=0; held_next[index]=-1;
                    hops_next=hops_next+1;
                    if (held_alt[index]) turns_next=turns_next+1;
                end
            end
        end
        for (node=0;node<16;node=node+1) begin
            local_held_next[node]=local_held[node];
            if (local_held[node]>=0) begin
                index=local_held[node];
                input_busy[index]=1; input_busy[index^1]=1; output_busy[5*node+LOCAL]=1;
                out_valid[node]=!reset; out_id[16*node +: 16]=packet[index];
                if (out_ready[node]) begin occupied_next[index]=0; local_held_next[node]=-1; end
            end
            for (step=0;step<10;step=step+1) begin
                candidate=node*10+(rotation+step)%10;
                if (occupied[candidate] && !input_busy[candidate]) begin
                    dst=int'(dest[candidate]); dx=dst%4-node%4; dy=dst/4-node/4;
                    other=-1; alt=0;
                    if (dx<0) want=WEST;
                    else if (dx==0 && dy==0) want=LOCAL;
                    else if (dx==0) want=(dy<0 ? NORTH : SOUTH);
                    else begin
                        want=EAST;
                        if (ADAPTIVE && dy!=0) other=(dy<0 ? NORTH : SOUTH);
                    end
                    if (want==LOCAL) begin
                        if (!output_busy[5*node+LOCAL]) begin
                            out_valid[node]=!reset; out_id[16*node +: 16]=packet[candidate];
                            output_busy[5*node+LOCAL]=1; input_busy[candidate^1]=1;
                            if (out_ready[node]) occupied_next[candidate]=0;
                            else local_held_next[node]=candidate;
                        end
                    end else begin
                        near1=neighbor(node,want);
                        near2=neighbor(node,other);
                        free1=0; free2=0; vc1=-1; vc2=-1;
                        if (near1>=0 && link_enable[4*node+want] && !output_busy[5*node+want]) begin
                            for (n=1;n>=0;n=n-1) begin
                                used_slot=10*near1+2*(want^1)+n;
                                if (!occupied[used_slot]) begin free1=free1+1; vc1=used_slot; end
                            end
                        end
                        if (near2>=0) begin
                            if (link_enable[4*node+other] && !output_busy[5*node+other]) begin
                                for (n=1;n>=0;n=n-1) begin
                                    used_slot=10*near2+2*(other^1)+n;
                                    if (!occupied[used_slot]) begin free2=free2+1; vc2=used_slot; end
                                end
                            end
                        end
                        if (free2>free1) begin chosen=other; tgt=vc2; alt=1; end
                        else begin chosen=want; tgt=vc1; end
                        if (tgt>=0) begin
                            output_index=5*node+chosen; output_busy[output_index]=1; input_busy[candidate^1]=1;
                            if (SPECULATIVE) begin
                                occupied_next[tgt]=1; dest_next[tgt]=dest[candidate];
                                packet_next[tgt]=packet[candidate]; occupied_next[candidate]=0;
                                hops_next=hops_next+1;
                                if (alt) turns_next=turns_next+1;
                            end else begin
                                held_next[output_index]=candidate; target_next[output_index]=tgt;
                                held_alt_next[output_index]=alt;
                            end
                        end
                    end
                end
            end
            index=10*node+8;
            if (occupied[index]) index=index+1;
            in_ready[node]=!occupied[index] && !reset;
            if (in_valid[node] && in_ready[node]) begin
                occupied_next[index]=1;
                dest_next[index]=destination[4*node +: 4]; packet_next[index]=in_id[16*node +: 16];
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            occupied<=0; rotation<=0; link_hops<=0; alternate_turns<=0;
            for (integer i=0;i<16;i=i+1) local_held[i]<=-1;
            for (integer i=0;i<160;i=i+1) begin dest[i]<=0; packet[i]<=0; end
            for (integer i=0;i<80;i=i+1) begin held[i]<=-1; target[i]<=-1; held_alt[i]<=0; end
        end else begin
            occupied<=occupied_next; rotation<=rotation_next;
            link_hops<=hops_next; alternate_turns<=turns_next;
            for (integer i=0;i<16;i=i+1) local_held[i]<=local_held_next[i];
            for (integer i=0;i<160;i=i+1) begin dest[i]<=dest_next[i]; packet[i]<=packet_next[i]; end
            for (integer i=0;i<80;i=i+1) begin
                held[i]<=held_next[i]; target[i]<=target_next[i]; held_alt[i]<=held_alt_next[i];
            end
        end
    end
endmodule
