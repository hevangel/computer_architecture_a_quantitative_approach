-- A tiny shared-memory machine with a selectable MEMORY CONSISTENCY MODEL (Chapter 5: models of memory consistency, litmus tests).
--
-- P cores run short programs of L instructions each:   ST addr,val  |  LD reg,addr  |  FENCE  |  (end).   Memory holds 4 words of 4 bits; each core has 2 registers.
-- Instruction word (8 bits):  op[7:6] (0 end, 1 ST, 2 LD, 3 FENCE) | addr[5:4] | for ST: value[3:0], for LD: register[1:0].
-- The machine is driven by an external SCHEDULER: each cycle the testbench picks ONE enabled ACTION (act_valid / act) -- either "core c executes its next instruction" or
-- "core c's store buffer drains entry j to memory" -- so every interleaving can be enumerated.  `enabled` shows which actions can be chosen now; when none is enabled the run is over.
--   MODEL 0  SC   (sequential consistency): a store goes to memory at once; loads read memory.
--   MODEL 1  TSO  (x86-like): each core has a FIFO STORE BUFFER.  A store enters the buffer, entries drain to memory in order, a core's own loads read its youngest buffered store to the
--                 same address (store-to-load FORWARDING) before memory, other cores see a store only when it has drained.  FENCE waits until the buffer is empty.
--   MODEL 2  PSO  : as TSO, but stores to DIFFERENT addresses may drain out of order (an entry can drain if no older entry has the same address).
-- All three models are multi-copy atomic: a drained store is visible to every core at once.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity consistency_model is
  generic (MODEL : natural := 0; P : positive := 4; L : positive := 3; SBD : positive := 3);
  port (
    clk, rst_n : in  std_logic;
    prog       : in  std_logic_vector(P*L*8-1 downto 0);
    act_valid  : in  std_logic;
    act        : in  natural range 0 to 255;
    enabled    : out std_logic_vector(P+P*SBD-1 downto 0);
    regs       : out std_logic_vector(P*2*4-1 downto 0);
    memv       : out std_logic_vector(4*4-1 downto 0)
  );
end entity;

architecture rtl of consistency_model is
  type nat_t is array (natural range <>) of natural;
  type nib_t is array (natural range <>) of std_logic_vector(3 downto 0);
  signal pc, sbc : nat_t(0 to P-1) := (others => 0);
  signal sba : nat_t(0 to P*SBD-1) := (others => 0);
  signal sbv : nib_t(0 to P*SBD-1) := (others => (others => '0'));
  signal mem : nib_t(0 to 3) := (others => (others => '0'));
  signal rg  : nib_t(0 to P*2-1) := (others => (others => '0'));
  type ins_t is array (0 to P-1) of std_logic_vector(7 downto 0);
  signal ins : ins_t;
begin
  comb : process (all)
    variable iv : ins_t;
    variable en : std_logic_vector(P+P*SBD-1 downto 0);
    variable ok : boolean;
  begin
    en := (others => '0');
    for c in 0 to P-1 loop
      if pc(c) < L then iv(c) := prog((c*L + pc(c))*8 + 7 downto (c*L + pc(c))*8); else iv(c) := (others => '0'); end if;
      case iv(c)(7 downto 6) is
        when "01" => if MODEL = 0 or sbc(c) < SBD then en(c) := '1'; end if;
        when "10" => en(c) := '1';
        when "11" => if sbc(c) = 0 then en(c) := '1'; end if;
        when others => null;
      end case;
      for j in 0 to SBD-1 loop
        ok := (MODEL /= 0) and (j < sbc(c));
        if MODEL = 1 and j /= 0 then ok := false; end if;
        if MODEL = 2 then
          for k in 0 to SBD-1 loop if k < j and sba(c*SBD + k) = sba(c*SBD + j) then ok := false; end if; end loop;
        end if;
        if ok then en(P + c*SBD + j) := '1'; end if;
      end loop;
    end loop;
    ins <= iv;  enabled <= en;
  end process;
  reg_out : for i in 0 to P*2-1 generate regs(i*4 + 3 downto i*4) <= rg(i); end generate;
  mem_out : for a in 0 to 3 generate memv(a*4 + 3 downto a*4) <= mem(a); end generate;

  seq : process (clk, rst_n)
    variable ac, aj, ad : natural;
    variable lv : std_logic_vector(3 downto 0);
  begin
    if rst_n = '0' then
      pc <= (others => 0);  sbc <= (others => 0);  sba <= (others => 0);  sbv <= (others => (others => '0'));
      mem <= (others => (others => '0'));  rg <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if act_valid = '1' then
        if act < P then                                                              -- core `act` executes its next instruction
          ac := act;
          ad := to_integer(unsigned(ins(ac)(5 downto 4)));
          case ins(ac)(7 downto 6) is
            when "01" =>                                                             -- ST
              if MODEL = 0 then mem(ad) <= ins(ac)(3 downto 0);
              else sba(ac*SBD + sbc(ac)) <= ad;  sbv(ac*SBD + sbc(ac)) <= ins(ac)(3 downto 0);  sbc(ac) <= sbc(ac) + 1;
              end if;
            when "10" =>                                                             -- LD: youngest buffered store to the address (forwarding), else memory
              lv := mem(ad);
              if MODEL /= 0 then
                for k in 0 to SBD-1 loop if k < sbc(ac) and sba(ac*SBD + k) = ad then lv := sbv(ac*SBD + k); end if; end loop;
              end if;
              rg(ac*2 + to_integer(unsigned(ins(ac)(1 downto 0)))) <= lv;
            when others => null;                                                     -- FENCE
          end case;
          pc(ac) <= pc(ac) + 1;
        else                                                                         -- drain entry j of core c to memory
          ac := (act - P) / SBD;  aj := (act - P) mod SBD;
          mem(sba(ac*SBD + aj)) <= sbv(ac*SBD + aj);
          for k in 0 to SBD-2 loop
            if k >= aj then sba(ac*SBD + k) <= sba(ac*SBD + k + 1);  sbv(ac*SBD + k) <= sbv(ac*SBD + k + 1); end if;
          end loop;
          sbc(ac) <= sbc(ac) - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
