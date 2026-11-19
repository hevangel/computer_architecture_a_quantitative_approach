module mcs_combining_barrier #(
    parameter integer N=8,
    parameter bit TREE=1,
    parameter bit MCS=1
)(
    input logic clk, reset,
    input logic [N-1:0] lock_request, lock_release, barrier_arrive,
    output logic [N-1:0] owner, barrier_release,
    output logic [31:0] handoff_messages, barrier_messages, root_messages
);
    // Zero-based heap: leaves occupy N-1 .. 2*N-2.
    localparam integer LAST=2*N-2;
    logic [LAST:0] arrived, released;
    logic [N-1:0] pending, queued;
    integer tail, holder, delayed_node, delayed_prev;
    integer successor [0:N-1];
    logic release_wait;

    always @(posedge clk) begin : update
        logic [LAST:0] old_arrived, old_released;
        integer i, candidate, parent, fanout, old_holder;
        if (reset) begin
            owner <= 0; barrier_release <= 0;
            handoff_messages <= 0; barrier_messages <= 0; root_messages <= 0;
            arrived = 0; released = 0; pending = 0; queued = 0;
            release_wait = 0;
            tail = -1; holder = -1; delayed_node = -1; delayed_prev = -1;
            for (i=0; i<N; i=i+1) successor[i]=-1;
        end else begin
            old_arrived=arrived; old_released=released;
            for (i=0; i<N; i=i+1) begin
                if (barrier_arrive[i] && !old_arrived[N-1+i] && !old_released[0]) begin
                    arrived[N-1+i]=1;
                end
            end
            if (TREE) begin
                fanout=0; parent=0;
                for (i=0; i<N-1; i=i+1) begin
                    if (!old_arrived[i] && old_arrived[2*i+1] && old_arrived[2*i+2]) begin
                        arrived[i]=1; fanout=fanout+2;
                        if (i==0) parent=parent+2;
                    end
                end
                released[0]=old_arrived[0];
                for (i=1; i<=LAST; i=i+1) begin
                    if (!old_released[i] && old_released[(i-1)/2]) begin
                        released[i]=1; fanout=fanout+1;
                        if (i<=2) parent=parent+1;
                    end
                end
                barrier_messages <= barrier_messages+fanout;
                root_messages <= root_messages+parent;
            end else begin
                fanout=0;
                for (i=0; i<N; i=i+1)
                    if (arrived[N-1+i] && !old_arrived[N-1+i]) fanout=fanout+1;
                if (&old_arrived[LAST:N-1]) begin
                    released='1;
                    fanout=fanout+N;
                end
                barrier_messages <= barrier_messages+fanout;
                root_messages <= root_messages+fanout;
            end
            barrier_release <= released[LAST:N-1];
            if (&released[LAST:N-1]) begin arrived=0; released=0; end

            // One serialized exchange per cycle. Link publication takes a
            // further cycle, so an unlock can see a new tail before its link.
            old_holder=holder;
            candidate=-1;
            for (i=0; i<N; i=i+1) begin
                if (lock_request[i] && holder!=i && !queued[i]) pending[i]=1;
                if (pending[i] && candidate==-1) candidate=i;
            end
            if (MCS) begin
                if (delayed_prev>=0) successor[delayed_prev]=delayed_node;
                delayed_prev=-1; delayed_node=-1;
                if (candidate>=0) begin
                    pending[candidate]=0;
                    successor[candidate]=-1;
                    if (tail<0) holder=candidate;
                    else begin delayed_prev=tail; delayed_node=candidate; queued[candidate]=1; end
                    tail=candidate;
                end
                if (old_holder>=0 && (lock_release[old_holder] || release_wait)) begin
                    release_wait=1;
                    if (successor[holder]>=0) begin
                        holder=successor[holder]; queued[holder]=0; release_wait=0;
                        handoff_messages <= handoff_messages+1;
                    end else if (tail==holder) begin holder=-1; tail=-1; release_wait=0; end
                end
            end else begin
                if (holder>=0 && lock_release[holder]) begin
                    fanout=0;
                    for (i=0; i<N; i=i+1) if (pending[i]) fanout=fanout+1;
                    handoff_messages <= handoff_messages+fanout;
                    holder=-1;
                end
                if (holder==-1 && candidate>=0) begin pending[candidate]=0; holder=candidate; end
            end
            owner <= holder<0 ? {N{1'b0}} : ({{(N-1){1'b0}},1'b1} << holder);
        end
    end
endmodule
