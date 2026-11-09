-- Flit format and port numbering shared by the virtual-channel router and the network.
--   flit = ( type(1:0) | vc(1:0) | payload(31:0) )          FW = 36 bits
--   type : 00 body, 01 head, 10 tail, 11 head+tail (single-flit packet)
--   vc   : the virtual channel (input buffer) this flit occupies at the NEXT router; the router rewrites it hop by hop
--   payload (every flit)   (15:0)  packet id        (23:16) flit index within the packet
--   payload (head flits)   (27:24) destination x    (31:28) destination y        (body/tail: (31:24) unused)
library ieee;
use ieee.std_logic_1164.all;

package vc_pkg is
  constant FW : positive := 36;
  constant T_BODY   : std_logic_vector(1 downto 0) := "00";
  constant T_HEAD   : std_logic_vector(1 downto 0) := "01";
  constant T_TAIL   : std_logic_vector(1 downto 0) := "10";
  constant T_SINGLE : std_logic_vector(1 downto 0) := "11";
  constant P_N : natural := 0;  constant P_E : natural := 1;  constant P_S : natural := 2;  constant P_W : natural := 3;  constant P_L : natural := 4;
  -- y grows towards the south; the local port connects to the node itself
end package;
