library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all;
entity tb_prf_rename_ooo is end;
architecture sim of tb_prf_rename_ooo is
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal init_we,valid,pred,check_conservation:std_logic:='0';
 signal init_reg,dst,src1,src2,dbg_reg:unsigned(2 downto 0):=(others=>'0'); signal init_data:unsigned(31 downto 0):=(others=>'0'); signal op:unsigned(1 downto 0):=(others=>'0');
 signal ready,recover,taken,idle:std_logic; signal recover_id,p_recover_id:unsigned(7 downto 0); signal dbg_value,issued,committed,squashed,recoveries,ooo:unsigned(31 downto 0); signal front,arch,count:unsigned(3 downto 0);
 signal p_reset:std_logic:='1'; signal p_init,p_valid,p_done,p_pred:std_logic:='0'; signal p_ready,p_idle,p_recover:std_logic; signal p_op:unsigned(1 downto 0):=to_unsigned(2,2); signal p_free_bits:std_logic_vector(15 downto 0); signal p_squashed:unsigned(31 downto 0);
 signal p_free:unsigned(4 downto 0); signal p_count:unsigned(3 downto 0); signal p_value,p_issued,p_committed:unsigned(31 downto 0);
 signal branch_id:unsigned(7 downto 0):=(others=>'0');
 signal free_bits:std_logic_vector(15 downto 0); signal free_count:unsigned(4 downto 0); signal full_stalls:natural:=0;
begin
 clk<=not clk after 5 ns;
 dut:entity work.prf_rename_ooo port map(clk,reset,init_we,init_reg,init_data,valid,op,dst,src1,src2,pred,branch_id,ready,recover,taken,recover_id,idle,dbg_reg,dbg_value,front,arch,free_bits,free_count,count,issued,committed,squashed,recoveries,ooo);
 pressure:entity work.prf_rename_ooo generic map(NPHYS=>12) port map(
  clk=>clk,reset=>p_reset,init_we=>p_init,init_reg=>to_unsigned(0,3),init_data=>to_unsigned(1,32),
  issue_valid=>p_valid,issue_op=>p_op,issue_dst=>to_unsigned(0,3),issue_src1=>to_unsigned(0,3),issue_src2=>to_unsigned(0,3),issue_pred_taken=>p_pred,issue_branch_id=>to_unsigned(7,8),
  issue_ready=>p_ready,recover_valid=>p_recover,recover_taken=>open,recover_branch_id=>p_recover_id,idle=>p_idle,dbg_reg=>to_unsigned(0,3),dbg_value=>p_value,dbg_front=>open,dbg_arch=>open,dbg_free=>p_free_bits,free_count=>p_free,rob_count=>p_count,
  stat_issued=>p_issued,stat_committed=>p_committed,stat_squashed=>p_squashed,stat_recoveries=>open,stat_ooo=>open);
 process begin
  for k in 1 to 3 loop wait until falling_edge(clk); end loop; p_reset<='0'; wait until falling_edge(clk); p_init<='1'; wait until falling_edge(clk); p_init<='0';
  for k in 0 to 3 loop wait until falling_edge(clk); p_valid<='1'; wait for 1 ns; assert p_ready='1' report "unexpected early pressure" severity failure; wait until rising_edge(clk); wait for 1 ns; end loop;
  wait until falling_edge(clk); p_valid<='1'; wait for 1 ns;
  assert p_ready='0' and p_free=0 and p_count=4 report "free list did not independently block issue" severity failure;
  p_op<=to_unsigned(3,2); p_pred<='1'; wait for 1 ns; assert p_ready='1' report "branch should not need a physical destination" severity failure;
  wait until rising_edge(clk); wait for 1 ns; wait until falling_edge(clk); p_op<=to_unsigned(2,2); p_pred<='0'; wait for 1 ns;
  while p_ready/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
  wait until rising_edge(clk); wait for 1 ns; wait until falling_edge(clk); p_valid<='0';
  while p_idle/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
  assert p_free=4 and p_count=0 and p_value=1 and p_issued=6 and p_committed=6 report "pressure recovery" severity failure;
  for k in 0 to 2 loop
   wait until falling_edge(clk); if k=0 then p_op<=to_unsigned(3,2); else p_op<=to_unsigned(2,2); end if; p_valid<='1'; wait for 1 ns;
   assert p_ready='1' report "pressure branch issue" severity failure; wait until rising_edge(clk); wait for 1 ns;
  end loop;
  wait until falling_edge(clk); p_valid<='0'; while p_recover/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
  assert p_recover_id=7 and p_squashed=2 and p_free=4 and p_free_bits=x"0f00" report "restricted PRF recovery mask" severity failure;
  while p_idle/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
  assert p_free=4 and p_issued=9 and p_committed=7 and p_value=1 report "restricted PRF branch drain" severity failure;
  p_done<='1'; wait;
 end process;
 process(clk) begin if rising_edge(clk) and check_conservation='1' and reset='0' then
  assert to_integer(free_count)+8+to_integer(count)=16 report "free-list conservation" severity failure;
  if valid='1' and ready='0' and free_count=0 then full_stalls<=full_stalls+1; end if;
 end if; end process;
 process
  procedure setup(random_values:boolean) is
  begin
   wait until falling_edge(clk); reset<='1'; valid<='0'; init_we<='0'; check_conservation<='0'; for k in 1 to 2 loop wait until falling_edge(clk); end loop; reset<='0';
   for r in 0 to 7 loop
    wait until falling_edge(clk); init_we<='1'; init_reg<=to_unsigned(r,3);
    if random_values then
     case r is when 0=>init_data<=to_unsigned(3,32); when 1=>init_data<=to_unsigned(5,32); when 2=>init_data<=to_unsigned(7,32); when 3=>init_data<=to_unsigned(11,32); when 4=>init_data<=to_unsigned(13,32); when 5=>init_data<=to_unsigned(17,32); when 6=>init_data<=to_unsigned(19,32); when others=>init_data<=to_unsigned(23,32); end case;
    else
     case r is when 0=>init_data<=to_unsigned(2,32); when 1=>init_data<=to_unsigned(1,32); when 2=>init_data<=to_unsigned(3,32); when others=>init_data<=(others=>'0'); end case;
    end if;
    wait until falling_edge(clk); init_we<='0';
   end loop;
  end;
  procedure send(operation,d,a,b:natural; predicted:std_logic) is
  begin
   wait until falling_edge(clk); valid<='1'; op<=to_unsigned(operation,2); dst<=to_unsigned(d,3); src1<=to_unsigned(a,3); src2<=to_unsigned(b,3); pred<=predicted; branch_id<=to_unsigned(d,8); wait for 1 ns;
   while ready/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
   wait until rising_edge(clk); wait for 1 ns;
  end;
  procedure stop_sending is begin wait until falling_edge(clk); valid<='0'; end;
  procedure wait_recovery is variable t:natural:=0; begin while recover/='1' and t<200 loop wait until falling_edge(clk); wait for 1 ns; t:=t+1; end loop; assert t<200 report "recovery timeout" severity failure; end;
  procedure drain is variable t:natural:=0; begin while idle/='1' and t<2000 loop wait until falling_edge(clk); wait for 1 ns; t:=t+1; end loop; assert t<2000 report "drain timeout" severity failure; end;
  procedure expect_reg(r:natural; value:unsigned(31 downto 0)) is begin dbg_reg<=to_unsigned(r,3); wait for 1 ns; assert dbg_value=value and front=arch report "register " & integer'image(r) severity failure; end;
  type shadow_t is array(0 to 7) of unsigned(31 downto 0); variable shadow:shadow_t; variable seed,a,b:unsigned(31 downto 0):=to_unsigned(1949,32); variable kind,d,s1,s2:natural;
 begin
  setup(false);
  send(2,0,0,2,'0'); send(3,0,1,0,'0'); send(0,0,0,1,'0'); send(1,2,2,1,'0'); stop_sending;
  wait_recovery; dbg_reg<=to_unsigned(0,3); wait for 1 ns;
  assert taken='1' and squashed=2 and recoveries=1 and front=8 and arch=0 and free_bits=x"fe00" and count=2 report "older uncommitted mapping recovery" severity failure;
  for r in 1 to 7 loop dbg_reg<=to_unsigned(r,3); wait for 1 ns; assert front=to_unsigned(r,4) and arch=to_unsigned(r,4) report "surviving map" severity failure; end loop;
  drain; expect_reg(0,to_unsigned(6,32)); expect_reg(2,to_unsigned(3,32)); assert free_count=8 and count=0 report "first recovery leak" severity failure;
  setup(false);
  send(2,0,0,2,'0'); send(3,0,0,0,'0'); send(0,0,0,1,'0'); send(1,2,2,1,'0'); stop_sending;
  wait_recovery; dbg_reg<=to_unsigned(0,3); wait for 1 ns;
  assert taken='1' and squashed=2 and front=arch and arch=8 and free_bits=x"fe01" and count=1 report "older committed mapping lost" severity failure;
  drain; expect_reg(0,to_unsigned(6,32)); expect_reg(2,to_unsigned(3,32)); assert free_count=8 and count=0 report "second recovery leak" severity failure;
  setup(false);
  send(3,0,3,0,'1'); send(0,2,1,1,'0'); stop_sending; wait_recovery;
  assert taken='0' and squashed=1 report "not-taken recovery" severity failure; drain; expect_reg(2,to_unsigned(3,32));
  setup(false);
  send(3,0,1,0,'1'); send(0,2,1,1,'0'); stop_sending; drain; expect_reg(2,to_unsigned(2,32));
  assert recoveries=0 and squashed=0 and free_count=8 report "correct prediction discarded work" severity failure;
  setup(false);
  send(2,0,0,2,'0'); send(3,1,0,0,'0'); send(3,2,1,0,'0'); send(0,2,1,1,'0'); stop_sending;
  wait_recovery; assert recover_id=2 report "younger branch identifier" severity failure; wait until falling_edge(clk); wait for 1 ns; wait_recovery;
  assert recover_id=1 report "older branch identifier" severity failure;
  drain; expect_reg(0,to_unsigned(6,32)); expect_reg(2,to_unsigned(3,32));
  assert recoveries=2 and committed=2 and free_count=8 report "nested branch recovery" severity failure;
  setup(false);
  send(2,0,0,2,'0'); send(3,0,1,0,'0'); send(0,0,0,1,'0'); send(1,2,2,1,'0'); send(0,5,1,1,'0');
  wait_recovery; assert ready='0' and squashed=3 report "issue accepted during recovery notification" severity failure;
  wait until falling_edge(clk); valid<='0'; drain; expect_reg(0,to_unsigned(6,32)); expect_reg(2,to_unsigned(3,32)); expect_reg(5,to_unsigned(0,32));
  assert issued=5 and committed=2 and free_count=8 report "wrong-path request leaked" severity failure;
  setup(true); shadow:=(to_unsigned(3,32),to_unsigned(5,32),to_unsigned(7,32),to_unsigned(11,32),to_unsigned(13,32),to_unsigned(17,32),to_unsigned(19,32),to_unsigned(23,32));
  check_conservation<='1';
  for i in 0 to 119 loop
   seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32); kind:=to_integer(seed(30 downto 16)) mod 6; if kind=0 then kind:=2; elsif kind mod 2=1 then kind:=0; else kind:=1; end if; d:=2+(to_integer(seed(4 downto 2)) mod 6); s1:=to_integer(seed(10 downto 8)); s2:=to_integer(seed(14 downto 12)); a:=shadow(s1); b:=shadow(s2);
   case kind is when 0=>shadow(d):=a+b; when 1=>shadow(d):=a-b; when others=>shadow(d):=resize(a*b,32); end case;
   send(kind,d,s1,s2,'0');
  end loop;
  stop_sending; drain; check_conservation<='0';
  assert shadow(0)=x"00000003" and shadow(1)=x"00000005" and shadow(2)=x"fcbe7adc" and shadow(3)=x"7934b0a5" and shadow(4)=x"5819034d" and shadow(5)=x"084b09f0" and shadow(6)=x"58190350" and shadow(7)=x"f7b4f615" report "reference stream mismatch" severity failure;
  for r in 0 to 7 loop expect_reg(r,shadow(r)); end loop;
  assert free_count=8 and count=0 and committed=120 and ooo>0 and full_stalls>0 report "final conservation or out-of-order execution" severity failure;
  while p_done/='1' loop wait until falling_edge(clk); end loop;
  report "120 instructions, out-of-order completions=" & integer'image(to_integer(ooo)) & ", free-list stalls=" & integer'image(full_stalls); report "TEST PASSED"; finish;
 end process;
 process begin wait for 200 us; assert false report "timeout" severity failure; end process;
end;
