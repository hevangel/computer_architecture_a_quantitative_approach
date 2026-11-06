// MESI write-invalidate snooping coherence for P private caches sharing one bus (Chapter 5).
// The model tracks a single cache line (one word) -- enough to show every protocol transition.
// One CPU operation is performed atomically per clock when op_valid is high; the bus
// transaction, supplied data and write-back are visible combinationally in that cycle.
//
//   state   meaning
//   I  (0)  invalid
//   S  (1)  shared, clean, other caches may hold it
//   E  (2)  exclusive, clean, no other cache holds it  (write needs no bus transaction)
//   M  (3)  modified, dirty, only copy
//   bus_txn: 0 none | 1 BusRd (read miss) | 2 BusRdX (write miss) | 3 BusUpgr (write to S line)
module mesi_snoopy #(
    parameter int P      = 4,
    parameter int DATA_W = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     op_valid,
    input  logic [$clog2(P)-1:0]     op_core,
    input  logic                     op_write,
    input  logic [DATA_W-1:0]        op_wdata,
    output logic [DATA_W-1:0]        rdata,        // value returned by a read
    output logic [1:0]               bus_txn,
    output logic                     writeback,    // a Modified copy was flushed to memory
    output logic [2*P-1:0]           state_out,    // 2 bits per core
    output logic [DATA_W-1:0]        mem_out
);
  localparam logic [1:0] ST_I = 2'd0, ST_S = 2'd1, ST_E = 2'd2, ST_M = 2'd3;

  logic [1:0]        st    [0:P-1];
  logic [DATA_W-1:0] data  [0:P-1];
  logic [DATA_W-1:0] mem;

  logic [1:0]        nst   [0:P-1];
  logic [DATA_W-1:0] ndata [0:P-1];
  logic [DATA_W-1:0] nmem;

  int  c, owner;
  logic have_owner, other_valid;

  always_comb begin
    c = int'(op_core);
    for (int j = 0; j < P; j++) begin nst[j] = st[j]; ndata[j] = data[j]; end
    nmem = mem;  bus_txn = 2'd0;  writeback = 1'b0;  rdata = data[c];
    // snoop: find a dirty/exclusive owner among the other caches, and whether anyone else has a copy
    owner = 0; have_owner = 1'b0; other_valid = 1'b0;
    for (int j = 0; j < P; j++)
      if (j != c) begin
        if (st[j] != ST_I) other_valid = 1'b1;
        if (st[j] == ST_M || st[j] == ST_E) begin owner = j; have_owner = 1'b1; end
      end

    if (op_valid) begin
      if (!op_write) begin
        if (st[c] == ST_I) begin                                   // read miss: BusRd
          bus_txn = 2'd1;
          if (have_owner) begin
            rdata = data[owner];
            if (st[owner] == ST_M) begin nmem = data[owner]; writeback = 1'b1; end
            nst[owner] = ST_S;
          end else rdata = mem;
          ndata[c] = rdata;
          nst[c]   = other_valid ? ST_S : ST_E;
          for (int j = 0; j < P; j++) if (j != c && st[j] == ST_E) nst[j] = ST_S;
        end                                                         // read hit: no change
      end else begin
        case (st[c])
          ST_M: ;                                                   // write hit, already owned
          ST_E: nst[c] = ST_M;                                      // silent upgrade: no bus traffic
          ST_S: begin                                               // BusUpgr: invalidate other sharers
            bus_txn = 2'd3;
            for (int j = 0; j < P; j++) if (j != c) nst[j] = ST_I;
            nst[c] = ST_M;
          end
          default: begin                                            // BusRdX: fetch with intent to modify
            bus_txn = 2'd2;
            if (have_owner && st[owner] == ST_M) begin nmem = data[owner]; writeback = 1'b1; end
            for (int j = 0; j < P; j++) if (j != c) nst[j] = ST_I;
            nst[c] = ST_M;
          end
        endcase
        ndata[c] = op_wdata;
      end
    end
  end

  always_comb begin
    for (int j = 0; j < P; j++) state_out[2*j +: 2] = st[j];
    mem_out = mem;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int j = 0; j < P; j++) begin st[j] <= ST_I; data[j] <= '0; end
      mem <= '0;
    end else if (op_valid) begin
      for (int j = 0; j < P; j++) begin st[j] <= nst[j]; data[j] <= ndata[j]; end
      mem <= nmem;
    end
  end
endmodule
