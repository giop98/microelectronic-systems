library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity decode is
    generic (
        N_BIT_INSTR:    integer := 32;
        N_BIT_ADDR_RF:  integer := 5;
        N_BIT_DATA:     integer := 32;
        OPCODE_SIZE:    integer := 6;  -- Operation Code Size
        PC_SIZE:        integer := 32
    );
    port (
        CLK:                in std_logic;
        RST:                in std_logic;
        INSTR:              in std_logic_vector(N_BIT_INSTR - 1 downto 0);      -- Instruction
        ADD_WB:             in std_logic_vector(N_BIT_ADDR_RF-1 downto 0);      -- Address for the write back
        CPC:                in std_logic_vector(PC_SIZE-1 downto 0);            -- Current program counter
        RD1:                in std_logic_vector(N_BIT_DATA-1 downto 0);         -- Data coming from the read port 1 of the Data Path
        RD2:                in std_logic_vector(N_BIT_DATA-1 downto 0);         -- Data coming from the read port 2 of the Data Path
        RF2:                in std_logic;                                       -- RF Read Port 2 Enable signal
        HAZARD_TABLE_WR1:   in std_logic;                                       -- CU signal to enable Hazard Ctrl on the current RF WR address    
        WB_EN:              in std_logic;            
        PIPLIN_ID_EN:       in std_logic;
        JUMP_EN:            in std_logic;
        NPC_SEL:            in std_logic;
        BUSY_WINDOW:        out std_logic;
        HAZARD_SIG:         out std_logic;
        ADD_RS1:            out std_logic_vector(N_BIT_ADDR_RF-1 downto 0);     -- Address 1 that goes in the register file
        ADD_RS2:            out std_logic_vector(N_BIT_ADDR_RF-1 downto 0);     -- Address 2 that goes in the register file
        ADD_WS1:            out std_logic_vector(N_BIT_ADDR_RF-1 downto 0);     -- Address for the write back that goes in the register file
        INP1:               out std_logic_vector(N_BIT_DATA-1 downto 0);
        INP2:               out std_logic_vector(N_BIT_DATA-1 downto 0);
        NPC:                out std_logic_vector(PC_SIZE-1 downto 0);           -- Next program counter
        PC_OVF:             out std_logic;                                      -- Signal for PC overflow
        LGET:               out std_logic_vector(1 downto 0)                    -- Comparator output towards CU and DP
    );
end entity;

architecture structural of decode is

    component hazard_table is
        generic (
            N_REGS_LOG: integer := 8
        );
        port (
            CLK:            in std_logic;
            RST:            in std_logic;
            WR1:            in std_logic;       -- Enable write 1 signal
            WR2:            in std_logic;       -- Enable write 2 signal
            ADD_WR1:        in std_logic_vector(N_REGS_LOG-1 downto 0);     -- Address wirte 1 signal
            ADD_WR2:        in std_logic_vector(N_REGS_LOG-1 downto 0);     -- Address wirte 2 signal
            ADD_CHECK1:     in std_logic_vector(N_REGS_LOG-1 downto 0);     -- Address reader 1 signal
            ADD_CHECK2:     in std_logic_vector(N_REGS_LOG-1 downto 0);     -- Address reader 2 signal
            BUSY:           out std_logic;     -- Signal to identify that there is an hazard. When '1' there is an hazard, when '0' there are no hazard
            BUSY_WINDOW:    out std_logic
        );
    end component;


    component comparator is
        generic (
            NBIT: integer := 16
        );
        port (
            A:		in	std_logic_vector(NBIT-1 downto 0);
            B:		in	std_logic_vector(NBIT-1 downto 0);
            LGET:	out std_logic_vector(1 downto 0)
        );
    end component;

    component mux2_1 is
        generic (
            NBIT: integer:= 32
        );
    	port (
            a:	in	std_logic_vector(NBIT - 1 downto 0);
            b:	in	std_logic_vector(NBIT - 1 downto 0);
            s: 	in	std_logic;
            y:	out	std_logic_vector(NBIT - 1 downto 0)
        );
    end component;


    component P4_ADDER is
        generic (
            NBIT :		integer := 16
        );

        port (
            A:		    in	std_logic_vector(NBIT-1 downto 0);
            B:		    in	std_logic_vector(NBIT-1 downto 0);
            SUB_SUMN:	in	std_logic;
            S:		    out	std_logic_vector(NBIT-1 downto 0);
            Cout:	    out	std_logic
        );
    end component;


    constant i_CONSTANT_PC_ADD: std_logic_vector(PC_SIZE-1 downto 0) := std_logic_vector(to_unsigned(4, PC_SIZE));


    signal op_code: std_logic_vector(OPCODE_SIZE-1 downto 0);

    signal i_RS1: std_logic_vector(N_BIT_ADDR_RF-1 downto 0);
    signal i_RS2: std_logic_vector(N_BIT_ADDR_RF-1 downto 0);
    signal i_WS1: std_logic_vector(N_BIT_ADDR_RF-1 downto 0);
    signal i_INP2: std_logic_vector(N_BIT_DATA-1 downto 0);

    signal i_RS2_masked: std_logic_vector(N_BIT_ADDR_RF-1 downto 0);

    signal i_WR1: std_logic;
    signal i_WR2: std_logic;

    signal i_PC_OFFSET: std_logic_vector(PC_SIZE-1 downto 0); -- with sign ext -- TO THE ADDER NPC
    signal i_OFFSET_ADDER: std_logic_vector(PC_SIZE-1 downto 0); -- mux output, '4' or the passed immediate

    signal i_SEL_CMPB: std_logic;
    signal i_CMP_B: std_logic_vector(N_BIT_DATA-1 downto 0);

    signal i_NPC_ADDER: std_logic_vector(PC_SIZE-1 downto 0);

begin

    ADD_RS1 <= i_RS1;
    ADD_RS2 <= i_RS2_masked;
    ADD_WS1 <= i_WS1;
    INP2 <= i_INP2;

    i_RS2_masked <= i_RS2 when (RF2 = '1') else (others => '0');

    i_WR2 <= WB_EN;                              -- Inhibition of ADD_WB when DataPath's WB stage is off
    i_WR1 <= PIPLIN_ID_EN and HAZARD_TABLE_WR1;  -- Inhibition of Hazard Ctrl on current WR address when ID stage disabled or CU directly disables it
                                                 -- Writing on the Hazard Table only when the instruction is ready to go on EX stage (ID_EN = '1')

    op_code <= INSTR(N_BIT_INSTR-1 downto N_BIT_INSTR-OPCODE_SIZE);
    
    process(INSTR, op_code)
    begin

        i_PC_OFFSET <= (others => INSTR(N_BIT_INSTR-OPCODE_SIZE-1)); -- sign extension
        i_PC_OFFSET(N_BIT_INSTR-OPCODE_SIZE-1 downto 0) <= INSTR(N_BIT_INSTR-OPCODE_SIZE-1 downto 0);

        if (op_code /= "000010" and op_code /= "000011") then -- for branch instructions, the immediate is 16 bits wide
            i_PC_OFFSET <= (others => INSTR(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1)); -- sign extension
            i_PC_OFFSET(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1 downto 0) <= INSTR(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1 downto 0);
        end if;

    end process;

    process(op_code, INSTR)
    begin
 
        i_SEL_CMPB <= '1';

        if (op_code = "000000") then -- R_TYPE

            i_RS1 <= INSTR(N_BIT_INSTR-OPCODE_SIZE-1 downto N_BIT_INSTR-OPCODE_SIZE-N_BIT_ADDR_RF);
            i_RS2 <= INSTR(N_BIT_INSTR-OPCODE_SIZE-N_BIT_ADDR_RF-1 downto N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF);
            i_WS1 <= INSTR(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1 downto N_BIT_INSTR-OPCODE_SIZE-3*N_BIT_ADDR_RF);     -- RD field

            INP1 <= (others => '0');
            i_INP2 <= (others => '0');

        elsif (op_code = "000010") then -- J_TYPE: J

            i_RS1 <= (others => '0');
            i_RS2 <= (others => '0');
            i_WS1 <= (others => '0');

            INP1 <= (others => '0'); -- The new PC is computed by the DECODE, the EXEC stage won't be executed
            i_INP2 <= (others => '0');

        elsif (op_code = "000011" or op_code = "011110") then -- J_TYPE: JAL

            -- JAL so we have to execute ADDI R31, R0, PC
            i_RS1 <= (others => '0'); -- R0
            i_RS2 <= (others => '0');
            i_WS1 <= "11111"; -- R31

            -- The IMM is the CPC that will be written into R31
            INP1 <= std_logic_vector(TO_UNSIGNED(4, INP2'length));
            i_INP2 <= CPC;

        else -- I_TYPE

            if (op_code /= "000100" and op_code /= "000101") then -- if BEQZ, BNEZ => SEL MUST BE 1
                i_SEL_CMPB <= '0';
            end if;

            
            i_RS1 <= INSTR(N_BIT_INSTR-OPCODE_SIZE-1 downto N_BIT_INSTR-OPCODE_SIZE-N_BIT_ADDR_RF);
            i_RS2 <= INSTR(N_BIT_INSTR-OPCODE_SIZE-N_BIT_ADDR_RF-1 downto N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF);
            i_WS1 <= INSTR(N_BIT_INSTR-OPCODE_SIZE-N_BIT_ADDR_RF-1 downto N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF);
            
            INP1 <= (others => '0');
            
            i_INP2 <= (others => INSTR(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1));
            i_INP2(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1 downto 0) <= INSTR(N_BIT_INSTR-OPCODE_SIZE-2*N_BIT_ADDR_RF-1 downto 0);

        end if;

    end process;


    HAZARD_CTRL: hazard_table generic map(
        N_REGS_LOG => N_BIT_ADDR_RF
    ) port map(
        CLK => CLK,
        RST => RST,
        WR1 => i_WR1,
        WR2 => i_WR2,
        ADD_WR1 => i_WS1,
        ADD_WR2 => ADD_WB,
        ADD_CHECK1 => i_RS1,
        ADD_CHECK2 => i_RS2_masked,
        BUSY => HAZARD_SIG,
        BUSY_WINDOW => BUSY_WINDOW
    );

    MUX_CMPB: mux2_1 generic map(
        NBIT => N_BIT_DATA
    ) port map(
        a => RD2,
        b => i_INP2,
        s => i_SEL_CMPB,
        y => i_CMP_B
    );


    Cmp: comparator generic map(
        NBIT => N_BIT_DATA
    ) port map(
        A => RD1,
        B => i_CMP_B,
        LGET => LGET
    );

    MUX: mux2_1 generic map(
        NBIT => PC_SIZE
    ) port map(
        a => i_PC_OFFSET,
        b => i_CONSTANT_PC_ADD,
        s => JUMP_EN,
        y => i_OFFSET_ADDER
    );

    ADDER: P4_ADDER generic map(
        NBIT => PC_SIZE
    ) port map(
        A => CPC,
        B => i_OFFSET_ADDER,
        SUB_SUMN => '0',
        S => i_NPC_ADDER,
        Cout =>	PC_OVF
    );

    MUX_NPC: mux2_1 generic map(
        NBIT => PC_SIZE
    ) port map(
        a => RD1,
        b => i_NPC_ADDER,
        s => NPC_SEL,
        y => NPC
    );

end architecture structural;
