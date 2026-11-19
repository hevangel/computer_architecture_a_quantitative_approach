module split_bus_transient_msi #(
    parameter integer DATA_DELAY=2
)(
    input logic clk, reset, allow_data,
    input logic [1:0] req_valid,
    input logic [3:0] req_op, // per core: 0 read, 1 write, 2 evict
    input logic [63:0] req_data,
    output wire [1:0] req_ready,
    output logic [1:0] rsp_valid,
    output logic [63:0] rsp_data,
    output wire [7:0] cache_state,
    output logic [31:0] memory_word, upgrade_races
);
    localparam logic [3:0] I=0, S=1, M=2, IM_AD=3, IM_D=4, SM_AD=5, MI_A=6, IS_D=7;
    logic [3:0] state [0:1];
    logic [1:0] pending;
    logic [1:0] operation [0:1];
    logic [31:0] cache [0:1], write_data [0:1];
    logic active;
    logic bus_core, priority_core;
    integer response_delay;
    logic [31:0] bus_data;
    assign req_ready = ~pending & {2{!reset}};
    assign cache_state = {state[1],state[0]};

    always @(posedge clk) begin : controller
        integer i, selected, peer;
        logic [1:0] accept;
        if (reset) begin
            pending=0; active=0; priority_core=0;
            rsp_valid<=0; rsp_data<=0;
            memory_word=0; upgrade_races=0;
            for(i=0;i<2;i=i+1) begin
                state[i]=I; cache[i]=0; operation[i]=0; write_data[i]=0;
            end
        end else begin
            accept=req_valid & req_ready;
            rsp_valid<=0;
            // A single line may have only one ordered address transaction at
            // a time. Other requests are accepted into private pending slots.
            if (active) begin
                if (response_delay>0) response_delay=response_delay-1;
                else if (allow_data) begin
                    case (state[bus_core])
                        IM_D: begin
                            state[bus_core]=M; cache[bus_core]=write_data[bus_core];
                            rsp_data[32*bus_core +: 32]<=write_data[bus_core];
                        end
                        IS_D: begin
                            state[bus_core]=S; cache[bus_core]=bus_data;
                            rsp_data[32*bus_core +: 32]<=bus_data;
                        end
                        MI_A: begin state[bus_core]=I; memory_word=bus_data; end
                        default: ;
                    endcase
                    rsp_valid[bus_core]<=1;
                    pending[bus_core]=0;
                    active=0;
                end
            end else begin
                selected=-1;
                if (pending[priority_core]) selected=int'(priority_core);
                else if (pending[!priority_core]) selected=int'(!priority_core);
                if (selected>=0) begin
                    peer=1-selected;
                    priority_core=peer[0];
                    if ((operation[selected]==0 && state[selected]!=I) ||
                        (operation[selected]==1 && state[selected]==M) ||
                        (operation[selected]==2 && state[selected]!=MI_A)) begin
                        case (operation[selected])
                            0: rsp_data[32*selected +: 32]<=cache[selected];
                            1: begin
                                cache[selected]=write_data[selected];
                                rsp_data[32*selected +: 32]<=write_data[selected];
                            end
                            2: state[selected]=I;
                            default: ;
                        endcase
                        rsp_valid[selected]<=1;
                        pending[selected]=0;
                    end else begin
                        bus_core=selected[0]; active=1; response_delay=DATA_DELAY;
                        bus_data=memory_word;
                        case (operation[selected])
                            0: begin
                                if (state[peer]==M || state[peer]==MI_A) begin
                                    bus_data=cache[peer]; memory_word=bus_data;
                                    state[peer]=S;
                                end
                                state[selected]=IS_D;
                            end
                            1: begin
                                if (state[peer]==M || state[peer]==MI_A) begin
                                    bus_data=cache[peer]; memory_word=bus_data;
                                end
                                if (state[peer]==SM_AD) begin
                                    state[peer]=IM_AD;
                                    upgrade_races=upgrade_races+1;
                                end else if (state[peer]!=IM_AD) state[peer]=I;
                                state[selected]=IM_D;
                            end
                            2: bus_data=cache[selected];
                            default: ;
                        endcase
                    end
                end
            end
            for(i=0;i<2;i=i+1) begin
                if (accept[i]) begin
                    pending[i]=1;
                    operation[i]=req_op[2*i +: 2];
                    write_data[i]=req_data[32*i +: 32];
                    if (operation[i]==1) begin
                        if (state[i]==I) state[i]=IM_AD;
                        else if (state[i]==S) state[i]=SM_AD;
                    end else if (operation[i]==2 && state[i]==M) state[i]=MI_A;
                end
            end
        end
    end
endmodule
