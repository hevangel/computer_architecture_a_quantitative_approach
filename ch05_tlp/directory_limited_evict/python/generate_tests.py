from pathlib import Path
from directory_reference import Directory

root = Path(__file__).resolve().parent.parent
ops = [(0,0,0,0),(2,0,0,0),(7,0,1,0x55),(7,1,0,0),
       (0,0,0,0),(2,0,0,0),(4,0,0,0),(6,0,0,0),(7,0,1,0x99),
       (7,2,0,0),(1,0,0,0),(1,3,1,0x12345678),(3,3,0,0)]
state = 68421
def draw():
    global state
    state = (state * 1664525 + 1013904223) & 0xffffffff
    return state
for _ in range(256):
    node, block, write, value = draw(), draw(), draw(), draw()
    ops.append(((node >> 8) % 8, (block >> 8) % 4, (write >> 8) % 2, value))
dirs = [Directory(i) for i in range(3)]
sv = '''`timescale 1ns/1ps
module tb_directory_limited_evict;
 reg clk=0, reset=1, req_valid=0, req_write=0; reg [2:0] req_node=0,dbg_node=0; reg [1:0] req_block=0,dbg_block=0; reg [31:0] req_data=0;
 wire [2:0] resp_valid; wire [31:0] resp_data[0:2],inv[0:2],puts[0:2],putm[0:2],fetches[0:2],cache_data[0:2],mem[0:2]; wire [1:0] cs[0:2],ds[0:2],cb[0:2]; wire [7:0] targets[0:2];
 always #5 clk=~clk;
 genvar g; generate for(g=0;g<3;g=g+1) begin: d
 directory_limited_evict #(.MODE(g)) dut(clk,reset,req_valid,req_node,req_write,req_block,req_data,resp_valid[g],resp_data[g],inv[g],puts[g],putm[g],fetches[g],dbg_node,dbg_block,cs[g],ds[g],cb[g],cache_data[g],mem[g],targets[g]); end endgenerate
 initial begin
  @(negedge clk); reset=0;
'''
vhdl = '''library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all;
entity tb_directory_limited_evict is end;
architecture sim of tb_directory_limited_evict is
 type a32 is array(0 to 2) of unsigned(31 downto 0); type a2 is array(0 to 2) of unsigned(1 downto 0); type a8 is array(0 to 2) of std_logic_vector(7 downto 0);
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal valid,wr:std_logic:='0'; signal node,dnode:unsigned(2 downto 0):=(others=>'0'); signal blk,dblk:unsigned(1 downto 0):=(others=>'0'); signal data:unsigned(31 downto 0):=(others=>'0');
 signal rv:std_logic_vector(0 to 2); signal rd,inv,puts,putm,fetches,cd,mem:a32; signal cs,ds,cb:a2; signal targets:a8;
begin
 clk<=not clk after 5 ns;
 d:for g in 0 to 2 generate
 dut:entity work.directory_limited_evict generic map(MODE=>g) port map(clk,reset,valid,node,wr,blk,data,rv(g),rd(g),inv(g),puts(g),putm(g),fetches(g),dnode,dblk,cs(g),ds(g),cb(g),cd(g),mem(g),targets(g)); end generate;
 process begin
 wait until falling_edge(clk); reset<='0';
'''
for index,(node,block,write,value) in enumerate(ops):
 sv+=f"  @(negedge clk); req_valid=1; req_node=3'd{node}; req_block=2'd{block}; req_write=1'b{write}; req_data=32'h{value:08x}; dbg_node=3'd{node}; dbg_block=2'd{block};\n  @(negedge clk); req_valid=0; #1;\n"
 vhdl+=f" wait until falling_edge(clk); valid<='1'; node<=to_unsigned({node},3); blk<=to_unsigned({block},2); wr<='{write}'; data<=x\"{value:08X}\"; dnode<=to_unsigned({node},3); dblk<=to_unsigned({block},2);\n wait until falling_edge(clk); valid<='0'; wait for 1 ns;\n"
 for mode,d in enumerate(dirs):
  result=d.access(node,block,write,value); cstate,cblock,cdata=d.cache[node]; targets=sum(1<<x for x in d.targets(block));
  sv+=f"  if(!resp_valid[{mode}] || resp_data[{mode}]!==32'h{result:08x} || inv[{mode}]!==32'd{d.inv} || puts[{mode}]!==32'd{d.puts} || putm[{mode}]!==32'd{d.putm} || fetches[{mode}]!==32'd{d.fetch} || cs[{mode}]!==2'd{cstate} || cb[{mode}]!==2'd{cblock} || cache_data[{mode}]!==32'h{cdata:08x} || ds[{mode}]!==2'd{d.state[block]} || mem[{mode}]!==32'h{d.memory[block]:08x} || targets[{mode}]!==8'h{targets:02x}) $fatal(1,\"step {index} mode {mode}\");\n"
  vhdl+=f" assert rv({mode})='1' and rd({mode})=x\"{result:08X}\" and inv({mode})=to_unsigned({d.inv},32) and puts({mode})=to_unsigned({d.puts},32) and putm({mode})=to_unsigned({d.putm},32) and fetches({mode})=to_unsigned({d.fetch},32) and cs({mode})=to_unsigned({cstate},2) and cb({mode})=to_unsigned({cblock},2) and cd({mode})=x\"{cdata:08X}\" and ds({mode})=to_unsigned({d.state[block]},2) and mem({mode})=x\"{d.memory[block]:08X}\" and targets({mode})=x\"{targets:02X}\" report \"step {index} mode {mode}\" severity failure;\n"
 if index==2: assert [d.inv for d in dirs]==[2,2,4]
 if index==8: assert [d.inv for d in dirs]==[6,9,11]
sv+='  $display("TEST PASSED"); $finish; end\nendmodule\n'
vhdl+=' report "TEST PASSED"; finish; end process; end;\n'
(root/'sv/tb_directory_limited_evict.sv').write_text(sv)
(root/'vhdl/tb_directory_limited_evict.vhd').write_text(vhdl)
