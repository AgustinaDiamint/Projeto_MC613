library ieee; 
use ieee.std_logic_1164.all;
USE ieee.numeric_std.ALL;


entity create_piece is 
port (
  clock         : in  std_logic;
  reset         : in  std_logic;
  sync_reset    : in  std_logic;
  seed          : in  std_logic_vector (3 downto 0);
  en            : in  std_logic;
  piece         : out integer );
end create_piece;

architecture rtl of create_piece is  
signal r_lfsr : std_logic_vector (4 downto 1);
begin  
process (clock, reset) begin 
  if (reset = '1') then 
    r_lfsr   <= (others=>'1');
  elsif rising_edge(clock) then 
    if(sync_reset='1') then
      r_lfsr   <= seed;
    elsif (en = '1') then 
      r_lfsr(4) <= r_lfsr(1);
      r_lfsr(3) <= r_lfsr(4) xor r_lfsr(1);
      r_lfsr(2) <= r_lfsr(3);
      r_lfsr(1) <= r_lfsr(2);   
      
    end if; 
  end if; 
end process; 
piece <= to_integer(signed(r_lfsr));
end architecture rtl;
