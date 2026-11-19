`timescale 1ns/1ps
module mcs_case #(parameter integer N=8)(output logic done);
    logic clk=0, reset=1;
    logic [N-1:0] request=0, unlock=0, arrive=0;
    wire [N-1:0] queued_owner, central_owner, tree_release, central_release;
    wire [31:0] queue_handoff, central_handoff, tree_messages, root_tree, central_messages, root_central;
    mcs_combining_barrier #(.N(N)) tree (
        clk, reset, request, unlock, arrive, queued_owner, tree_release, queue_handoff, tree_messages, root_tree);
    mcs_combining_barrier #(.N(N),.TREE(0),.MCS(0)) central (
        clk, reset, request, unlock, arrive, central_owner, central_release, central_handoff, central_messages, root_central);
    always #5 clk=~clk;
    task tick;
        @(posedge clk); #1;
        if ((queued_owner & (queued_owner-1))!=0 || (central_owner & (central_owner-1))!=0)
            $fatal(1,"mutual exclusion N=%0d",N);
    endtask
    integer i, phase, delay_steps;
    initial begin
        done=0;
        tick; reset=0;
        // An arriving successor changes tail on the same edge as unlock.
        request=1; tick;
        request=2; unlock=1; tick;
        if (queued_owner!=1 || central_owner!=2) $fatal(1,"late link wait");
        request=0; unlock=0; tick;
        if (queued_owner!=2 || queue_handoff!=1) $fatal(1,"late link handoff");
        unlock=2; tick;
        if (queued_owner!=0 || central_owner!=0) $fatal(1,"uncontended release");
        reset=1; unlock=0; tick; reset=0;
        request=1; tick; request=~{{(N-1){1'b0}},1'b1}; tick; request=0;
        repeat(N) tick;
        for(i=0;i<N;i=i+1) begin
            if (queued_owner!=(1<<i) || central_owner!=(1<<i)) $fatal(1,"FIFO/order N=%0d i=%0d",N,i);
            unlock=1<<i; tick;
            if (queue_handoff!=((i+1<N) ? i+1 : N-1) ||
                central_handoff!=(i+1)*(2*N-2-i)/2)
                $fatal(1,"handoff traffic N=%0d i=%0d",N,i);
        end
        if (queued_owner!=0 || central_owner!=0) $fatal(1,"lock did not drain");
        unlock=0;

        for(phase=0;phase<2;phase=phase+1) begin
            for(i=0;i<N-1;i=i+1) begin
                arrive=1<<(phase==0 ? i : N-1-i); tick;
                if (tree_release!=0 || central_release!=0) $fatal(1,"early release");
            end
            tick; // Duplicate of the prior arrival.
            arrive=1<<(phase==0 ? N-1 : 0); tick; arrive=0;
            if (tree_release!=0 || central_release!=0) $fatal(1,"last arrival edge");
            for(delay_steps=1;delay_steps<=2*$clog2(N)+1;delay_steps=delay_steps+1) begin
                tick;
                if (central_release!==((delay_steps==1) ? {N{1'b1}} : {N{1'b0}}))
                    $fatal(1,"central release N=%0d",N);
                if (tree_release!==((delay_steps==2*$clog2(N)+1) ? {N{1'b1}} : {N{1'b0}}))
                    $fatal(1,"tree release N=%0d at %0d",N,delay_steps);
            end
            if (tree_messages!=(phase+1)*4*(N-1) || root_tree!=(phase+1)*4 ||
                central_messages!=(phase+1)*2*N || root_central!=central_messages)
                $fatal(1,"barrier traffic N=%0d",N);
            tick;
            if (tree_release!=0 || central_release!=0) $fatal(1,"release was not a pulse");
        end
        $display("N=%0d handoff %0d/%0d barrier root %0d/%0d",N,queue_handoff,central_handoff,root_tree,root_central);
        done=1;
    end
endmodule

module tb_mcs_combining_barrier;
    wire d2,d4,d8;
    mcs_case #(.N(2)) c2(d2);
    mcs_case #(.N(4)) c4(d4);
    mcs_case #(.N(8)) c8(d8);
    initial begin
        wait(d2 && d4 && d8);
        $display("TEST PASSED"); $finish;
    end
    initial begin #2000; $fatal(1,"timeout"); end
endmodule
