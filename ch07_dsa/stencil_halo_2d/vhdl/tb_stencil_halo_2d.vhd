library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
entity tb_stencil_halo_2d is end;
architecture tb of tb_stencil_halo_2d is
  signal clk:std_logic:='0'; signal reset:std_logic:='1';
  signal load_valid,start,wrap_edges,out_ready:std_logic:='0';
  signal load_addr:unsigned(5 downto 0):=(others=>'0'); signal load_data:unsigned(7 downto 0):=(others=>'0');
  signal filter_mode,shift_direction,out_tile:unsigned(1 downto 0):=(others=>'0');
  signal busy,out_valid:std_logic; signal out_values:std_logic_vector(255 downto 0); signal load_count:unsigned(6 downto 0); signal scratch_read_count:unsigned(7 downto 0);
begin
  clk<=not clk after 5 ns;
  dut:entity work.stencil_halo_2d port map(clk,reset,load_valid,load_addr,load_data,start,wrap_edges,filter_mode,shift_direction,busy,out_valid,out_ready,out_tile,out_values,load_count,scratch_read_count);
  process
    file vectors:text open read_mode is "../../../../ch07_dsa/stencil_halo_2d/golden.txt";
    variable ln:line; variable expected:std_logic_vector(255 downto 0);
  begin
    wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
    for y in 0 to 7 loop
      for x in 0 to 7 loop
        load_valid<='1'; load_addr<=to_unsigned(y*8+x,6); load_data<=to_unsigned((y*37+x*19+y*x*3) mod 256,8);
        wait until falling_edge(clk);
      end loop;
    end loop;
    load_valid<='0'; assert load_count=64 report "load count mismatch" severity failure;
    for wrap in 0 to 1 loop
      for mode in 0 to 2 loop
        if wrap=1 then wrap_edges<='1'; else wrap_edges<='0'; end if;
        filter_mode<=to_unsigned(mode,2); start<='1'; wait until falling_edge(clk); start<='0';
        for tile in 0 to 3 loop
          assert not endfile(vectors) report "short vectors" severity failure;
          readline(vectors,ln); hread(ln,expected);
          for n in 0 to 49 loop exit when out_valid='1'; wait until falling_edge(clk); end loop;
          assert out_valid='1' and out_tile=tile and out_values=expected report "stencil mismatch" severity failure;
          if tile<2 then assert scratch_read_count=36+24*tile report "tile read count" severity failure;
          else assert scratch_read_count=96+24*(tile-2) report "tile read count" severity failure; end if;
          load_valid<='1'; load_addr<=to_unsigned(0,6); load_data<=to_unsigned(255,8);
          for stall in 1 to 2 loop
            wait until falling_edge(clk);
            assert out_valid='1' and out_tile=tile and out_values=expected report "stall mismatch" severity failure;
          end loop;
          load_valid<='0'; out_ready<='1'; wait until falling_edge(clk); out_ready<='0';
        end loop;
        assert busy='0' and load_count=64 and scratch_read_count=120 report "completion or fetch count" severity failure;
      end loop;
    end loop;
    for wrap in 0 to 1 loop
      for dir in 0 to 3 loop
        if wrap=1 then wrap_edges<='1'; else wrap_edges<='0'; end if;
        filter_mode<=to_unsigned(3,2); shift_direction<=to_unsigned(dir,2); start<='1';
        wait until falling_edge(clk); start<='0';
        for t in 0 to 3 loop
          assert not endfile(vectors) report "short shift vectors" severity failure;
          readline(vectors,ln); hread(ln,expected);
          for n in 0 to 49 loop exit when out_valid='1'; wait until falling_edge(clk); end loop;
          assert out_valid='1' and out_tile=t and out_values=expected report "shift mismatch" severity failure;
          out_ready<='1'; wait until falling_edge(clk); out_ready<='0';
        end loop;
        assert busy='0' and load_count=64 and scratch_read_count=120 report "fetch count in shift" severity failure;
      end loop;
    end loop;
    assert endfile(vectors) report "extra vectors" severity failure;
    file_close(vectors); file_open(vectors,"../../../../ch07_dsa/stencil_halo_2d/golden.txt",read_mode);
    wait until falling_edge(clk); wrap_edges<='0'; filter_mode<=to_unsigned(0,2); start<='1'; out_ready<='1';
    wait until falling_edge(clk); start<='0'; load_valid<='1'; load_addr<=to_unsigned(0,6); load_data<=to_unsigned(255,8);
    for i in 1 to 10 loop wait until falling_edge(clk); end loop; load_valid<='0';
    for t in 0 to 3 loop
      readline(vectors,ln); hread(ln,expected);
      for n in 0 to 49 loop exit when out_valid='1'; wait until falling_edge(clk); end loop;
      assert out_valid='1' and out_tile=t and out_values=expected report "ready-high tile mismatch" severity failure;
      wait until falling_edge(clk);
    end loop;
    out_ready<='0'; assert busy='0' and load_count=64 and scratch_read_count=120 report "ready-high completion" severity failure;
    file_close(vectors); report "TEST PASSED"; finish;
  end process;
  process begin wait for 30 us; assert false report "timeout" severity failure; end process;
end architecture;
