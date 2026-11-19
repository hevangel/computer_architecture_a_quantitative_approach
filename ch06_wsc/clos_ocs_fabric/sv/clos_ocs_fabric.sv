module clos_ocs_fabric (
    input logic clk, reset,
    input logic [31:0] in_valid,
    output logic [31:0] in_ready,
    input logic [95:0] in_destination,
    input logic [511:0] in_id,
    output logic [31:0] out_valid,
    input logic [7:0] out_ready,
    output logic [511:0] out_id,
    input logic cfg_valid,
    input logic [3:0] cfg_cross,
    output logic cfg_ready,
    output logic [3:0] active_cross
);
    logic [31:0] queued, queued_next, flight, flight_next;
    logic [2:0] destination [0:31], destination_next [0:31];
    logic [15:0] packet [0:31], packet_next [0:31];
    logic [15:0] flight_id [0:31], flight_id_next [0:31];
    logic [3:0] desired, desired_next, active_next;
    logic changing, changing_next;

    // Each of four 2x2 optical switches permutes two leaf ports across
    // two secondary spines. The common spine guarantees connectivity.
    function automatic integer secondary(input integer leaf, input logic [3:0] mapping);
        secondary=1+(leaf/4)+(leaf%2 ^ int'(mapping[leaf/2]));
    endfunction

    integer rotation, rotation_next;
    always @* begin : route
        integer source, index, dest, spine, candidate, step, lane, port_index;
        logic [31:0] used_ingress_link;
        queued_next=queued;
        flight_next=flight;
        desired_next=desired;
        active_next=active_cross;
        changing_next=changing;
        rotation_next=(rotation+1)%32;
        used_ingress_link=0;
        cfg_ready=!changing && !reset;
        in_ready=~queued & {32{!reset}};
        out_valid=flight & {32{!reset}};
        out_id=0;
        for (index=0;index<32;index=index+1) begin
            destination_next[index]=destination[index];
            packet_next[index]=packet[index];
            flight_id_next[index]=flight_id[index];
            out_id[16*index +: 16]=flight_id[index];
            if (flight[index] && out_ready[index/4]) flight_next[index]=0;
        end
        if (cfg_valid && cfg_ready) begin
            desired_next=cfg_cross;
            changing_next=1;
        end
        if (changing_next) begin
            if (flight_next==0) begin
                active_next=desired_next;
                changing_next=0;
            end
        end else begin
            for (step=0;step<32;step=step+1) begin
                candidate=(rotation+step)%32;
                source=candidate/4;
                dest=int'(destination[candidate]);
                if (queued[candidate]) begin
                    for (lane=0;lane<2;lane=lane+1) begin
                        if (lane==0) spine=0; else spine=secondary(source,active_cross);
                        port_index=4*dest+spine;
                        if (queued_next[candidate] && !used_ingress_link[4*source+spine] &&
                            !flight_next[port_index] &&
                            (spine==0 || spine==secondary(dest,active_cross))) begin
                            used_ingress_link[4*source+spine]=1;
                            flight_next[port_index]=1;
                            flight_id_next[port_index]=packet[candidate];
                            queued_next[candidate]=0;
                        end
                    end
                end
            end
        end
        for (index=0;index<32;index=index+1) begin
            if (in_valid[index] && in_ready[index]) begin
                queued_next[index]=1;
                destination_next[index]=in_destination[3*index +: 3];
                packet_next[index]=in_id[16*index +: 16];
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            queued<=0; flight<=0; changing<=0; desired<=0; active_cross<=0; rotation<=0;
            for (integer i=0;i<32;i=i+1) begin
                destination[i]<=0; packet[i]<=0; flight_id[i]<=0;
            end
        end else begin
            queued<=queued_next; flight<=flight_next; changing<=changing_next;
            desired<=desired_next; active_cross<=active_next; rotation<=rotation_next;
            for (integer i=0;i<32;i=i+1) begin
                destination[i]<=destination_next[i]; packet[i]<=packet_next[i];
                flight_id[i]<=flight_id_next[i];
            end
        end
    end
endmodule
