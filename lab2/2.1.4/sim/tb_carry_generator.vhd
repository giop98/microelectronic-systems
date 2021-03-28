library ieee; 
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TB_CARRY_GENERATOR is 
end TB_CARRY_GENERATOR; 

architecture TEST of TB_CARRY_GENERATOR is

	component CARRY_GENERATOR is
		generic (
			NBIT :		integer := 32;
			NBIT_PER_BLOCK: integer := 4);
		port (
			A :		in	std_logic_vector(NBIT-1 downto 0);
			B :		in	std_logic_vector(NBIT-1 downto 0);
			Cin :	in	std_logic;
			Co :	out	std_logic_vector((NBIT/NBIT_PER_BLOCK)-1 downto 0));
	end component;

	constant N: integer := 4;
	constant K: integer := 4;

	signal a, b: std_logic_vector(N-1 downto 0);
	signal co: std_logic_vector((N/K)-1 downto 0);
	signal cin: std_logic;

begin

	DUT: CARRY_GENERATOR generic map(N, K) port map(a, b, cin, co);

	process
	begin 

		cin <= '1';
		a <= "0001";
		b <= "0001";

		wait for 5 ns;

		a <= "1111";
		b <= "0101";
		wait for 5 ns;
		a <= "0000";
		b <= "0000";
		wait for 5 ns;

		wait;
	end process;
	-- process
	-- 	variable carry: std_logic;
	-- begin

	-- 	for i in 0 to 2**N-1 loop
	-- 		for j in 0 to 2**N-1 loop
	-- 			a <= std_logic_vector(TO_UNSIGNED(i, a'length));
	-- 			b <= std_logic_vector(TO_UNSIGNED(j, a'length));

	-- 			wait for 1 ns;

	-- 			for z in 0 to N-1 loop
	-- 				carry := (a(z) and b(z)) or ((a(z) or b(z)) and cin);
	-- 				if ((z+1) mod K = 0) then
	-- 					assert co(z/K) = carry report "Error!";
	-- 				end if;
	-- 			end loop;

	-- 			wait for 1 ns;
	-- 		end loop;
	-- 	end loop;
		
	-- 	wait;
	-- end process;

end TEST;
