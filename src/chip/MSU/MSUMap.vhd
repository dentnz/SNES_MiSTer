library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity MSUMap is
	port(
		MCLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic := '1';
		
		CA   			: in std_logic_vector(23 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		CPURD_N		: in std_logic;
		CPUWR_N		: in std_logic;
		
		PA				: in std_logic_vector(7 downto 0);
		PARD_N		: in std_logic;
		PAWR_N		: in std_logic;
		
		ROMSEL_N		: in std_logic;
		RAMSEL_N		: in std_logic;
		
		SYSCLKF_CE	: in std_logic;
		SYSCLKR_CE	: in std_logic;
		
		REFRESH		: in std_logic;
		
		PAL			: in std_logic;
		
		IRQ_N			: out std_logic;

		ROM_ADDR		: out std_logic_vector(22 downto 0);
		ROM_Q			: in  std_logic_vector(15 downto 0);
		ROM_CE_N		: out std_logic;
		ROM_OE_N		: out std_logic;
		ROM_WORD		: out std_logic;
		
		BSRAM_ADDR	: out std_logic_vector(19 downto 0);
		BSRAM_D		: out std_logic_vector(7 downto 0);
		BSRAM_Q		: in  std_logic_vector(7 downto 0);
		BSRAM_CE_N	: out std_logic;
		BSRAM_OE_N	: out std_logic;
		BSRAM_WE_N	: out std_logic;

		MAP_ACTIVE      : out std_logic;
		MAP_CTRL		: in std_logic_vector(7 downto 0);
		ROM_MASK		: in std_logic_vector(23 downto 0);
		BSRAM_MASK	    : in std_logic_vector(23 downto 0);
		
		track_out   : out std_logic_vector(15 downto 0);

		BRK_OUT		: out std_logic;
		DBG_REG		: in std_logic_vector(7 downto 0) := (others => '0');
		DBG_DAT_IN	: in std_logic_vector(7 downto 0) := (others => '0');
		DBG_DAT_OUT	: out std_logic_vector(7 downto 0);
		DBG_DAT_WR	: in std_logic := '0'
	);
end MSUMap;

architecture rtl of MSUMap is

	--signal ROM_A		: std_logic_vector(22 downto 0);
	--signal BWRAM_A 	: std_logic_vector(17 downto 0);
	signal MAP_SEL		: std_logic;

	component MSU is
		port (
			CLK         : in  std_logic;
			RST_N       : in  std_logic;
			ENABLE      : in  std_logic;

			RD_N        : in  std_logic;
			WR_N        : in  std_logic;
			ADDR        : in  std_logic_vector(23 downto 0);
			DIN         : in  std_logic_vector(7 downto 0);
		    DOUT        : out std_logic_vector(7 downto 0);

			track_out   : out std_logic_vector(15 downto 0)
		);
	end component;

begin

	-- @todo always forcing this active for now
	MAP_ACTIVE <= 1;
	
	-- Instantiate the verilog
	MSU_instance : component MSU
	port map(
		CLK         => MCLK,
		RST_N		=> RST_N,
		ENABLE		=> ENABLE,

		RD_N		=> CPURD_N,
		WR_N		=> CPUWR_N,

		ADDR		=> CA,
		DIN			=> DI,
		DOUT		=> DO,

		track_out   => track_out
	);

end rtl;