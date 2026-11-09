// Directory-based MSI cache coherence (Chapter 5: distributed shared memory, directory protocols).
//
// P nodes, each with a private cache holding one line per block, NB blocks, ONE HOME DIRECTORY (with the memory) that keeps, per block, a state and a SHARER BIT VECTOR:
//   directory state   U  uncached (memory has the only copy)     S  shared by the nodes whose bit is set (memory is up to date)     M  modified: ONE sharer bit = the owner
//   cache state       I invalid    S shared (read-only, clean)    M modified (read/write, dirty)
// Unlike the snooping bus of mesi_snoopy there is no broadcast: every transaction is a few POINT-TO-POINT MESSAGES between the requester, the home and the nodes named by the directory.
// A node sends its request to the home; the home serialises requests (one transaction at a time) and, depending on the directory state, replies directly or involves the other nodes:
//   read miss,  dir U or S : request, data reply                                                   2 messages, 2 hops
//   read miss,  dir M      : request, FETCH to the owner (owner -> S), data to the home (memory is updated), data reply     4 messages, 4 hops
//   write miss, dir U      : request, data reply                                                   2 messages, 2 hops
//   write, dir S, nobody else shares (incl. the requester upgrading its own S copy)              2 messages, 2 hops
//   write, dir S, k other sharers : request, k INVALIDATES (parallel), k acknowledgements, reply   2k + 2 messages, 4 hops
//   write miss, dir M      : request, FETCH+INVALIDATE to the owner, data to the home, reply       4 messages, 4 hops
// Timing: every message takes LAT cycles; a node or the home acts in the cycle a message arrives.  A request accepted in cycle t therefore completes (resp_valid) in cycle t + hops*LAT + 1;
// a hit answers in cycle t + 1.  The model applies the state changes when the transaction completes (the home serialises, so nobody can observe the intermediate states).
// Statistics count messages by type.  Caches are large enough to hold every block (no replacements; see the exercises).
module directory_msi #(
    parameter int P   = 4,
    parameter int NB  = 4,
    parameter int LAT = 2,
    parameter int DW  = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     req_valid,
    input  logic [$clog2(P)-1:0]     req_node,
    input  logic                     req_write,
    input  logic [$clog2(NB)-1:0]    req_blk,
    input  logic [DW-1:0]            req_wdata,
    output logic                     req_ready,
    output logic                     resp_valid,
    output logic [DW-1:0]            resp_data,
    output logic [31:0]              stat_req, stat_rep, stat_inv, stat_ack, stat_fetch, stat_wb, stat_hits, stat_misses,
    input  logic [$clog2(P)-1:0]     dbg_node,
    input  logic [$clog2(NB)-1:0]    dbg_blk,
    output logic [1:0]               dbg_cstate,
    output logic [DW-1:0]            dbg_cdata,
    output logic [1:0]               dbg_dstate,
    output logic [P-1:0]             dbg_dsharers,
    output logic [DW-1:0]            dbg_mem
);
  localparam logic [1:0] C_I = 2'd0, C_S = 2'd1, C_M = 2'd2;
  localparam logic [1:0] D_U = 2'd0, D_S = 2'd1, D_M = 2'd2;

  logic [1:0]    cst  [0:P*NB-1];
  logic [DW-1:0] cdat [0:P*NB-1];
  logic [1:0]    dst  [0:NB-1];
  logic [P-1:0]  dsh  [0:NB-1];
  logic [DW-1:0] mem  [0:NB-1];
  assign dbg_cstate = cst[int'(dbg_node)*NB + int'(dbg_blk)];
  assign dbg_cdata  = cdat[int'(dbg_node)*NB + int'(dbg_blk)];
  assign dbg_dstate = dst[dbg_blk];
  assign dbg_dsharers = dsh[dbg_blk];
  assign dbg_mem    = mem[dbg_blk];

  logic busy;
  int   cnt;
  logic [$clog2(P)-1:0] r_node;  logic r_wr;  logic [$clog2(NB)-1:0] r_blk;  logic [DW-1:0] r_wdata;

  assign req_ready = !busy;

  // ---- decode of the current request: the incoming one while idle, the latched one while a transaction is in flight ----
  int  c, b, k, owner;
  logic wr, hit, owner_found;
  logic [1:0] cs, ds;
  logic [P-1:0] sh, others;
  logic [DW-1:0] wd;
  int  hops;
  always_comb begin
    c  = busy ? int'(r_node) : int'(req_node);
    b  = busy ? int'(r_blk)  : int'(req_blk);
    wr = busy ? r_wr : req_write;
    wd = busy ? r_wdata : req_wdata;
    cs = cst[c*NB + b];  ds = dst[b];  sh = dsh[b];
    others = sh;  others[c] = 1'b0;
    k = 0;  owner = 0;  owner_found = 1'b0;
    for (int j = 0; j < P; j++) begin
      if (others[j]) k++;
      if (sh[j] && j != c) begin owner = j; owner_found = 1'b1; end
    end
    hit = (!wr && cs != C_I) || (wr && cs == C_M);
    if (!wr)                    hops = (ds == D_M) ? 4 : 2;
    else if (ds == D_U)         hops = 2;
    else if (ds == D_S)         hops = (k == 0) ? 2 : 4;
    else                        hops = 4;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;  cnt <= 0;  resp_valid <= 1'b0;  resp_data <= '0;
      r_node <= '0;  r_wr <= 1'b0;  r_blk <= '0;  r_wdata <= '0;
      stat_req <= '0; stat_rep <= '0; stat_inv <= '0; stat_ack <= '0; stat_fetch <= '0; stat_wb <= '0; stat_hits <= '0; stat_misses <= '0;
      for (int i = 0; i < P*NB; i++) begin cst[i] <= C_I; cdat[i] <= '0; end
      for (int i = 0; i < NB; i++) begin dst[i] <= D_U; dsh[i] <= '0; mem[i] <= DW'(32'hA0 + i); end
    end else begin
      resp_valid <= 1'b0;
      if (!busy) begin
        if (req_valid) begin
          if (hit) begin                                                     // a hit never leaves the node
            stat_hits <= stat_hits + 1;  resp_valid <= 1'b1;
            if (wr) begin cdat[c*NB + b] <= wd; resp_data <= wd; end else resp_data <= cdat[c*NB + b];
          end else begin                                                     // a miss starts a transaction of `hops` message hops
            stat_misses <= stat_misses + 1;
            busy <= 1'b1;  cnt <= hops * LAT;
            r_node <= req_node;  r_wr <= req_write;  r_blk <= req_blk;  r_wdata <= req_wdata;
          end
        end
      end else begin
        if (cnt == 1) begin                                                  // the reply arrives: the transaction completes
          busy <= 1'b0;  cnt <= 0;  resp_valid <= 1'b1;
          stat_req <= stat_req + 1;  stat_rep <= stat_rep + 1;
          if (!wr) begin
            if (ds == D_M) begin                                             // fetch from the owner, which keeps a Shared copy; memory is updated
              stat_fetch <= stat_fetch + 1;  stat_wb <= stat_wb + 1;
              mem[b] <= cdat[owner*NB + b];  cst[owner*NB + b] <= C_S;
              cdat[c*NB + b] <= cdat[owner*NB + b];  resp_data <= cdat[owner*NB + b];
              dsh[b] <= (P'(1) << owner) | (P'(1) << c);
            end else begin
              cdat[c*NB + b] <= mem[b];  resp_data <= mem[b];
              dsh[b] <= sh | (P'(1) << c);
            end
            cst[c*NB + b] <= C_S;  dst[b] <= D_S;
          end else begin
            if (ds == D_M) begin                                             // fetch + invalidate the owner
              stat_fetch <= stat_fetch + 1;  stat_wb <= stat_wb + 1;
              mem[b] <= cdat[owner*NB + b];  cst[owner*NB + b] <= C_I;
            end else if (ds == D_S && k > 0) begin                           // invalidate the other sharers, collect the acknowledgements
              stat_inv <= stat_inv + k;  stat_ack <= stat_ack + k;
              for (int j = 0; j < P; j++) if (others[j]) cst[j*NB + b] <= C_I;
            end
            cst[c*NB + b] <= C_M;  cdat[c*NB + b] <= wd;  resp_data <= wd;
            dst[b] <= D_M;  dsh[b] <= P'(1) << c;
          end
        end else cnt <= cnt - 1;
      end
    end
  end
endmodule
