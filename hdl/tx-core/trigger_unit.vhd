-- ####################################
-- # Project: Yarr
-- # Author: Timon Heim
-- # E-Mail: timon.heim at cern.ch
-- # Comments: Trigger Logic
-- ####################################

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity trigger_unit is
	generic (
		g_TRIG_WORD_LENGTH : integer := 5
    );
	port (
		clk_i 	: in  std_logic;
		rst_n_i	: in  std_logic;
		
		-- Serial Trigger Out
		trig_o : out std_logic;
		trig_pulse_o : out std_logic;
		
		-- Trigger In (async)
		ext_trig_i	: in std_logic;
		
		-- Config
		trig_word_i : in std_logic_vector(g_TRIG_WORD_LENGTH-1 downto 0); -- Trigger command
		trig_freq_i : in std_logic_vector(31 downto 0); -- Number of clock cycles between triggers
		trig_time_i : in std_logic_vector(63 downto 0); -- Clock cycles
		trig_count_i : in std_logic_vector(31 downto 0); -- Fixed number of triggers
		trig_conf_i	: in std_logic_vector(3 downto 0); -- Internal, external, pseudo random, 
		trig_en_i : in std_logic;
		trig_done_o : out std_logic
	);
end trigger_unit;

architecture Behavioral of trigger_unit is
	function log2_ceil(N : natural) return positive is
	begin
		if N <= 2 then
		  return 1;
		elsif N mod 2 = 0 then
		  return 1 + log2_ceil(N/2);
		else
		  return 1 + log2_ceil((N+1)/2);
		end if;
	end;
    -- Signals
    signal bit_count : unsigned(log2_ceil(g_TRIG_WORD_LENGTH) downto 0);
    signal sreg      : std_logic_vector(g_TRIG_WORD_LENGTH-1 downto 0);
	signal trig_pulse : std_logic;
	
	-- Registers
	signal trig_word : std_logic_vector(g_TRIG_WORD_LENGTH-1 downto 0);
	signal trig_freq : std_logic_vector(31 downto 0);
	signal trig_time : std_logic_vector(63 downto 0);
	signal trig_count : std_logic_vector(31 downto 0);
	signal trig_conf : stD_logic_vector(3 downto 0);
	signal trig_en : std_logic;
	signal trig_done : std_logic;
	
	-- Counters
	signal stopwatch_cnt : unsigned(63 downto 0);
	signal int_trig_cnt : unsigned(31 downto 0);
	signal freq_cnt : unsigned(31 downto 0);
	
	-- Sync
	signal trig_en_d0 : std_logic;
	signal trig_en_d1 : std_logic;
	signal trig_en_pos : std_logic;
	signal trig_en_neg : std_logic;
	signal ext_trig_d0 : std_logic;
	signal ext_trig_d1 : std_logic;
	signal ext_trig_pos : std_logic;
	
begin
	-- Done conditions
	done_proc : process(clk_i, rst_n_i)
	begin
		if (rst_n_i = '0') then
			trig_done <= '0';
		elsif rising_edge(clk_i) then
			if (trig_en = '0') then -- Reset done on disable
				trig_done <= '0';
			elsif (trig_conf = x"0") then -- External
				trig_done <= '1';
			elsif (trig_conf = x"1") then -- Internal time
				if (stopwatch_cnt = unsigned(trig_time)) then
					trig_done <= '1';
				end if;
			elsif (trig_conf = x"2") then -- Internal count
				if (int_trig_cnt = unsigned(trig_count)) then
					trig_done <= '1';
				end if;
			--elsif (trig_conf = x"3") then -- Pseudo Random
			end if;
		end if;
	end process done_proc;
	
	-- Stopwatch
	stopwatch_proc : process (clk_i, rst_n_i)
	begin
		if (rst_n_i = '0') then
			stopwatch_cnt <= (others => '0');
		elsif rising_edge(clk_i) then
			if (trig_done = '1') then
				stopwatch_cnt <= (others => '0');
			elsif (trig_en = '1') then
				stopwatch_cnt <= stopwatch_cnt + 1;
			end if;
		end if;
	end process stopwatch_proc;
	
	-- Trigger count
	int_trig_cnt_proc : process (clk_i, rst_n_i)
	begin
		if (rst_n_i = '0') then
			int_trig_cnt <= (others => '0');
		elsif rising_edge(clk_i) then
			if (trig_done = '1') then
				int_trig_cnt <= (others => '0');
			elsif (trig_en = '1' and trig_pulse = '1') then
				int_trig_cnt <= int_trig_cnt + 1;
			end if;
		end if;
	end process int_trig_cnt_proc;
	
	-- Trigger Pulser
	trig_pulse_o <= trig_pulse;
	trig_pulse_proc : process(clk_i, rst_n_i)
	begin
		if (rst_n_i = '0') then
			trig_pulse <= '0';
			freq_cnt <= (others => '0');
		elsif rising_edge(clk_i) then
			if (trig_conf = x"0") then -- Pusling on External rising edge
				if (trig_en = '1' and ext_trig_pos = '1') then
					trig_pulse <= '1';
				else
					trig_pulse <= '0';
				end if;
			else -- Pulsing on requency counter
				if (trig_done = '1') then
					trig_pulse <= '0';
					freq_cnt <= (others => '0');
				elsif (trig_en = '1') then
					if (freq_cnt = unsigned(trig_freq)) then	
						freq_cnt <= (others => '0');
						trig_pulse <= '1';
					else
						freq_cnt <= freq_cnt + 1;
						trig_pulse <= '0';
					end if;
				end if;
			end if;
		end if;
	end process trig_pulse_proc;

    -- Tie offs
    trig_o <= sreg(0);
    -- Serializer proc
    serialize: process(clk_i, rst_n_i)
    begin
		if (rst_n_i = '0') then
			sreg <= (others => '0');
			bit_count <= (others => '0');
		elsif rising_edge(clk_i) then
			if (trig_pulse = '1') then
				sreg <= trig_word;
			else
				sreg <= '0' & sreg(g_TRIG_WORD_LENGTH-1 downto 1);
			end if;
		end if;
    end process serialize;
	
	-- Sync proc
	sync_proc : process (clk_i, rst_n_i)
	begin
		if (rst_n_i = '0') then
			trig_word <= (others => '0');
			trig_freq <= (others => '0');
			trig_time <= (others => '0');
			trig_count <= (others => '0');
			trig_conf <= (others => '0');
			trig_en <= '0';
			trig_done_o <= '0';
			ext_trig_d0 <= '0';
			ext_trig_d0 <= '0';
			ext_trig_pos <= '0';
			trig_en_d0 <= '0';
			trig_en_d1 <= '0';
			trig_en_pos <= '0';
			trig_en_neg <= '0';
		elsif rising_edge(clk_i) then
			ext_trig_d0 <= ext_trig_i;
			ext_trig_d1 <= ext_trig_d0;
			if (ext_trig_d1 = '0' and ext_trig_d0 = '1') then
				ext_trig_pos <= '1';
			else
				ext_trig_pos <= '1';
			end if;
		
			trig_en_d0 <= trig_en_i;
			trig_en_d1 <= trig_en_d0;
			if (trig_en_d1 = '0' and trig_en_d0 = '1') then
				trig_en_pos <= '1';
				trig_en_neg <= '0';
			elsif (trig_en_d1 = '1' and trig_en_d0 = '0') then
				trig_en_pos <= '0';
				trig_en_neg <= '1';			
			else
				trig_en_neg <= '0';
				trig_en_pos <= '0';
			end if;
			
			if (trig_en_pos = '1') then		
				trig_word <= trig_word_i;
				trig_freq <= trig_freq_i;
				trig_time <= trig_time_i;
				trig_count <= trig_count_i;
				trig_conf <= trig_conf_i;
				trig_en <= '1';
			elsif (trig_en_neg = '1') then
				trig_en <= '0';
			end if;
			
			trig_done_o <= trig_done;
		end if;
	end process;
	
end Behavioral;

