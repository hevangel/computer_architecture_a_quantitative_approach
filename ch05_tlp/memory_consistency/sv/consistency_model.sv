// A tiny shared-memory machine with a selectable MEMORY CONSISTENCY MODEL (Chapter 5: models of memory consistency, litmus tests).
//
// P cores run short programs of L instructions each:   ST addr,val  |  LD reg,addr  |  FENCE  |  (end).   Memory holds 4 words of 4 bits; each core has 2 registers.
// Instruction word (8 bits):  op[7:6] (0 end, 1 ST, 2 LD, 3 FENCE) | addr[5:4] | for ST: value[3:0], for LD: register[1:0].
// The machine is driven by an external SCHEDULER: each cycle the testbench picks ONE enabled ACTION (act_valid / act) -- either "core c executes its next instruction" or
// "core c's store buffer drains entry j to memory" -- so every interleaving can be enumerated.  `enabled` shows which actions can be chosen now; when none is enabled the run is over.
//   MODEL 0  SC   (sequential consistency): a store goes to memory at once; loads read memory.
//   MODEL 1  TSO  (x86-like): each core has a FIFO STORE BUFFER.  A store enters the buffer, entries drain to memory in order, a core's own loads read its youngest buffered store to the
//                 same address (store-to-load FORWARDING) before memory, other cores see a store only when it has drained.  FENCE waits until the buffer is empty.
//   MODEL 2  PSO  : as TSO, but stores to DIFFERENT addresses may drain out of order (an entry can drain if no older entry has the same address).
// All three models are multi-copy atomic: a drained store is visible to every core at once.
module consistency_model #(
    parameter int MODEL = 0,
    parameter int P     = 4,
    parameter int L     = 3,
    parameter int SBD   = 3
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [P*L*8-1:0]     prog,
    input  logic                 act_valid,
    input  logic [7:0]           act,
    output logic [P+P*SBD-1:0]   enabled,
    output logic [P*2*4-1:0]     regs,
    output logic [4*4-1:0]       memv
);
  localparam int NACT = P + P*SBD;
  logic [1:0]  pc  [0:P-1];
  logic [2:0]  sbc [0:P-1];
  logic [1:0]  sba [0:P*SBD-1];
  logic [3:0]  sbv [0:P*SBD-1];
  logic [3:0]  mem [0:3];
  logic [3:0]  rg  [0:P*2-1];

  logic [7:0] ins [0:P-1];
  always_comb begin
    for (int c = 0; c < P; c++) begin
      ins[c] = (int'(pc[c]) < L) ? prog[(c*L + int'(pc[c]))*8 +: 8] : 8'h00;
      enabled[c] = 1'b0;
      case (ins[c][7:6])
        2'd1: enabled[c] = (MODEL == 0) || (int'(sbc[c]) < SBD);
        2'd2: enabled[c] = 1'b1;
        2'd3: enabled[c] = (sbc[c] == 3'd0);
        default: enabled[c] = 1'b0;
      endcase
      for (int j = 0; j < SBD; j++) begin
        logic ok;
        ok = (MODEL != 0) && (j < int'(sbc[c]));
        if (MODEL == 1 && j != 0) ok = 1'b0;
        if (MODEL == 2)
          for (int k = 0; k < SBD; k++) if (k < j && sba[c*SBD + k] == sba[c*SBD + j]) ok = 1'b0;
        enabled[P + c*SBD + j] = ok;
      end
    end
    for (int i = 0; i < P*2; i++) regs[i*4 +: 4] = rg[i];
    for (int a = 0; a < 4; a++) memv[a*4 +: 4] = mem[a];
  end

  int ac, aj, la, fnd;  logic [3:0] lv;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int c = 0; c < P; c++) begin pc[c] <= '0; sbc[c] <= '0; end
      for (int i = 0; i < P*SBD; i++) begin sba[i] <= '0; sbv[i] <= '0; end
      for (int a = 0; a < 4; a++) mem[a] <= '0;
      for (int i = 0; i < P*2; i++) rg[i] <= '0;
    end else if (act_valid) begin
      if (int'(act) < P) begin                                                       // core `act` executes its next instruction
        ac = int'(act);
        case (ins[ac][7:6])
          2'd1: begin                                                                 // ST
            if (MODEL == 0) mem[ins[ac][5:4]] <= ins[ac][3:0];
            else begin sba[ac*SBD + int'(sbc[ac])] <= ins[ac][5:4];  sbv[ac*SBD + int'(sbc[ac])] <= ins[ac][3:0];  sbc[ac] <= sbc[ac] + 1'b1; end
          end
          2'd2: begin                                                                 // LD: youngest buffered store to the address (forwarding), else memory
            lv = mem[ins[ac][5:4]];
            if (MODEL != 0) for (int k = 0; k < SBD; k++) if (k < int'(sbc[ac]) && sba[ac*SBD + k] == ins[ac][5:4]) lv = sbv[ac*SBD + k];
            rg[ac*2 + int'(ins[ac][1:0])] <= lv;
          end
          default: ;                                                                  // FENCE
        endcase
        pc[ac] <= pc[ac] + 1'b1;
      end else begin                                                                  // drain entry j of core c to memory
        ac = (int'(act) - P) / SBD;  aj = (int'(act) - P) % SBD;
        mem[sba[ac*SBD + aj]] <= sbv[ac*SBD + aj];
        for (int k = 0; k < SBD - 1; k++) if (k >= aj) begin sba[ac*SBD + k] <= sba[ac*SBD + k + 1];  sbv[ac*SBD + k] <= sbv[ac*SBD + k + 1]; end
        sbc[ac] <= sbc[ac] - 1'b1;
      end
    end
  end
endmodule
