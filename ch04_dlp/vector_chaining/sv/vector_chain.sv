// Pipelined vector machine with CHAINING (Chapter 4 / Appendix G).
// Three pipelined functional units -- MEM (LV/SV, one memory pipe), ADD and MUL -- each take ONE element per cycle.  Vector instructions are issued
// IN ORDER, one per cycle, to the unit they need; a unit is then busy for vl cycles and a following instruction may start as soon as the last element has
// entered it.  A result element appears in its vector register LAT cycles after the element entered the unit.
//   CHAIN = 1 : a consumer element may enter its unit the cycle after the producer element was written (the units are CHAINED, elements are forwarded
//               through the register file as they appear);   CHAIN = 0 : a consumer waits until the whole source vector has been written.
// Hazards: RAW is handled per element through a count of valid elements per register (avail); WAW/WAR are checked at issue (the destination must have no
// pending writer and no unfinished reader).  The destination of an instruction must differ from its sources.  vl is fixed while the machine runs a program.
//   op 0 LV  vd,[base+i]     op 1 SV  vs1,[base+i]     op 2 ADDV vd,vs1,vs2    op 3 SUBV vd,vs1,vs2
//   op 4 MULV vd,vs1,vs2     op 5 MULVS vd,vs1,scalar  op 6 ADDVS vd,vs1,scalar
// Observability: st_valid[u]/st_tag pulse when the first element of an instruction enters unit u (u: 0 MEM, 1 ADD, 2 MUL); idle is high when nothing is in flight.
module vector_chain #(
    parameter bit CHAIN   = 1'b1,
    parameter int LD_LAT  = 6,
    parameter int ADD_LAT = 4,
    parameter int MUL_LAT = 7
) (
    input  logic        clk, rst_n,
    // setup ports, use only while idle
    input  logic        ld_we,  input logic [2:0] ld_reg,  input logic [3:0] ld_idx,  input logic [31:0] ld_data,
    input  logic [2:0]  rd_reg, input logic [3:0] rd_idx,  output logic [31:0] rd_data,
    input  logic        mem_we, input logic [7:0] mem_addr, input logic [31:0] mem_wdata,
    input  logic [7:0]  mem_raddr, output logic [31:0] mem_rdata,
    input  logic [4:0]  vl,
    // instruction issue
    input  logic        ins_valid,
    input  logic [2:0]  ins_op, ins_vd, ins_vs1, ins_vs2,
    input  logic signed [31:0] ins_scalar,
    input  logic [7:0]  ins_base, ins_tag,
    output logic        ins_ready,
    output logic [2:0]  st_valid,
    output logic [23:0] st_tag,
    output logic        idle
);
  localparam int MVL = 16, VREGS = 8, DEP = 8;
  logic signed [31:0] vrf [0:VREGS*MVL-1];
  logic signed [31:0] mem [0:255];
  assign rd_data  = vrf[int'(rd_reg)*MVL + int'(rd_idx)];
  assign mem_rdata = mem[mem_raddr];

  function automatic int unit_of(input logic [2:0] op);
    case (op) 3'd0, 3'd1: return 0;  3'd2, 3'd3, 3'd6: return 1;  default: return 2; endcase
  endfunction
  function automatic bit uses_s1(input logic [2:0] op);  return op != 3'd0;  endfunction
  function automatic bit uses_s2(input logic [2:0] op);  return op == 3'd2 || op == 3'd3 || op == 3'd4;  endfunction
  function automatic bit has_dst(input logic [2:0] op);  return op != 3'd1;  endfunction
  function automatic int exit_stage(input int u);  return (u == 0 ? LD_LAT : (u == 1 ? ADD_LAT : MUL_LAT)) - 2;  endfunction

  // unit state
  logic        u_act [0:2];
  logic [2:0]  u_op [0:2], u_vd [0:2], u_vs1 [0:2], u_vs2 [0:2];
  logic signed [31:0] u_sc [0:2];
  logic [7:0]  u_base [0:2], u_tag [0:2];
  logic [4:0]  u_idx [0:2];
  // register status
  logic [4:0]  avail [0:VREGS-1];
  logic        pw    [0:VREGS-1];
  logic [3:0]  readers [0:VREGS-1];
  // result delay lines, index u*DEP + stage
  logic        dl_v   [0:3*DEP-1];
  logic [2:0]  dl_dst [0:3*DEP-1];
  logic [4:0]  dl_idx [0:3*DEP-1];
  logic signed [31:0] dl_dat [0:3*DEP-1];

  // ---- combinational: which units move an element, element results, issue readiness ----
  logic        enter [0:2], lastel [0:2], ufree [0:2];
  logic signed [31:0] res [0:2], opa [0:2], opb [0:2];
  logic [4:0]  sa [0:2];
  always_comb begin
    for (int u = 0; u < 3; u++) begin
      logic s1ok, s2ok;
      s1ok = !uses_s1(u_op[u]) || (avail[u_vs1[u]] > u_idx[u]);
      s2ok = !uses_s2(u_op[u]) || (avail[u_vs2[u]] > u_idx[u]);
      enter[u]  = u_act[u] && s1ok && s2ok;
      lastel[u] = enter[u] && ({1'b0, u_idx[u]} + 6'd1 == {1'b0, vl});
      ufree[u]  = !u_act[u] || lastel[u];
      opa[u] = vrf[int'(u_vs1[u])*MVL + int'(u_idx[u])];
      opb[u] = vrf[int'(u_vs2[u])*MVL + int'(u_idx[u])];
      case (u_op[u])
        3'd0:    res[u] = mem[8'(u_base[u] + {3'b0, u_idx[u]})];
        3'd2:    res[u] = opa[u] + opb[u];
        3'd3:    res[u] = opa[u] - opb[u];
        3'd4:    res[u] = opa[u] * opb[u];
        3'd5:    res[u] = opa[u] * u_sc[u];
        3'd6:    res[u] = opa[u] + u_sc[u];
        default: res[u] = 32'sd0;
      endcase
      st_valid[u] = enter[u] && u_idx[u] == 5'd0;
      st_tag[8*u +: 8] = u_tag[u];
    end
  end
  logic hz_ok;
  always_comb begin
    hz_ok = !has_dst(ins_op) || (!pw[ins_vd] && readers[ins_vd] == 4'd0);
    ins_ready = ufree[unit_of(ins_op)] && hz_ok;
    idle = !(u_act[0] || u_act[1] || u_act[2]);
    for (int r = 0; r < VREGS; r++) if (pw[r]) idle = 1'b0;
  end

  // ---- clocked ----
  logic [3:0] n_readers [0:VREGS-1];
  int iu;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int u = 0; u < 3; u++) begin u_act[u] <= 1'b0;  u_idx[u] <= '0; end
      for (int r = 0; r < VREGS; r++) begin avail[r] <= 5'd16;  pw[r] <= 1'b0;  readers[r] <= '0; end
      for (int i = 0; i < 3*DEP; i++) dl_v[i] <= 1'b0;
      for (int i = 0; i < VREGS*MVL; i++) vrf[i] <= '0;
      for (int i = 0; i < 256; i++) mem[i] <= '0;
    end else begin
      if (ld_we)  begin vrf[int'(ld_reg)*MVL + int'(ld_idx)] <= ld_data;  avail[ld_reg] <= 5'd16; end
      if (mem_we) mem[mem_addr] <= mem_wdata;

      // result delay lines shift; new elements enter stage 0
      for (int u = 0; u < 3; u++) begin
        for (int k = 1; k < DEP; k++) begin
          dl_v[u*DEP + k] <= dl_v[u*DEP + k - 1];  dl_dst[u*DEP + k] <= dl_dst[u*DEP + k - 1];
          dl_idx[u*DEP + k] <= dl_idx[u*DEP + k - 1];  dl_dat[u*DEP + k] <= dl_dat[u*DEP + k - 1];
        end
        dl_v[u*DEP] <= enter[u] && has_dst(u_op[u]);  dl_dst[u*DEP] <= u_vd[u];  dl_idx[u*DEP] <= u_idx[u];  dl_dat[u*DEP] <= res[u];
      end
      // write-back at the exit stage of each unit
      for (int u = 0; u < 3; u++) begin
        if (dl_v[u*DEP + exit_stage(u)]) begin
          vrf[int'(dl_dst[u*DEP + exit_stage(u)])*MVL + int'(dl_idx[u*DEP + exit_stage(u)])] <= dl_dat[u*DEP + exit_stage(u)];
          if (CHAIN) avail[dl_dst[u*DEP + exit_stage(u)]] <= dl_idx[u*DEP + exit_stage(u)] + 5'd1;
          if ({1'b0, dl_idx[u*DEP + exit_stage(u)]} + 6'd1 == {1'b0, vl}) begin
            pw[dl_dst[u*DEP + exit_stage(u)]] <= 1'b0;
            avail[dl_dst[u*DEP + exit_stage(u)]] <= vl;
          end
        end
      end
      // units: advance, store, finish
      for (int r = 0; r < VREGS; r++) n_readers[r] = readers[r];
      for (int u = 0; u < 3; u++) begin
        if (enter[u]) begin
          u_idx[u] <= u_idx[u] + 5'd1;
          if (u_op[u] == 3'd1) mem[8'(u_base[u] + {3'b0, u_idx[u]})] <= opa[u];
          if (lastel[u]) begin
            u_act[u] <= 1'b0;
            if (uses_s1(u_op[u])) n_readers[u_vs1[u]] = n_readers[u_vs1[u]] - 4'd1;
            if (uses_s2(u_op[u])) n_readers[u_vs2[u]] = n_readers[u_vs2[u]] - 4'd1;
          end
        end
      end
      // issue
      if (ins_valid && ins_ready) begin
        iu = unit_of(ins_op);
        u_act[iu] <= 1'b1;  u_op[iu] <= ins_op;  u_vd[iu] <= ins_vd;  u_vs1[iu] <= ins_vs1;  u_vs2[iu] <= ins_vs2;
        u_sc[iu] <= ins_scalar;  u_base[iu] <= ins_base;  u_tag[iu] <= ins_tag;  u_idx[iu] <= 5'd0;
        if (has_dst(ins_op)) begin pw[ins_vd] <= 1'b1;  avail[ins_vd] <= 5'd0; end
        if (uses_s1(ins_op)) n_readers[ins_vs1] = n_readers[ins_vs1] + 4'd1;
        if (uses_s2(ins_op)) n_readers[ins_vs2] = n_readers[ins_vs2] + 4'd1;
      end
      for (int r = 0; r < VREGS; r++) readers[r] <= n_readers[r];
    end
  end
endmodule
