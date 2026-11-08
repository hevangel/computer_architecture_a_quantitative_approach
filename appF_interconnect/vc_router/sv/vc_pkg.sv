// Flit format and port numbering shared by the virtual-channel router and the network.
//   flit = { type[1:0] | vc[1:0] | payload[31:0] }          FW = 36 bits
//   type : 0 body, 1 head, 2 tail, 3 head+tail (single-flit packet)
//   vc   : the virtual channel (input buffer) this flit occupies at the NEXT router; the router rewrites it hop by hop
//   payload (every flit)   [15:0]  packet id        [23:16] flit index within the packet
//   payload (head flits)   [27:24] destination x    [31:28] destination y        (body/tail: [31:24] unused)
package vc_pkg;
  localparam int FW = 36;
  localparam logic [1:0] T_BODY = 2'd0, T_HEAD = 2'd1, T_TAIL = 2'd2, T_SINGLE = 2'd3;
  localparam int P_N = 0, P_E = 1, P_S = 2, P_W = 3, P_L = 4;      // y grows towards the south; the local port connects to the node itself
endpackage
