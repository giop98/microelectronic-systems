library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.myTypes.all;

entity tb_dp is
end entity;

architecture test of tb_dp is

    component DP is

        generic (
            N_BIT_DATA          : integer := 32;    -- generic data path bit width
            N_BIT_ADDR_RF       : integer := 5;     -- address bit number
            N_OPSEL             : integer := 2;     -- number of bit needed for the ALU operations
            N_BIT_MEM_ADDR      : integer := 10;    -- number of bit needed for the address of the Data Memory
            N_BIT_RF_MEM_ADDR   : integer := 10     -- number of bit needed for the address of the memory used to PUSH/POP data from the register file. We call this memory, RF memory
        );

        port (
        
            Clk :   in std_logic;     -- CLock
            Rst :   in std_logic;     -- Reset: Active-Low
    
    
            EN1 :  in std_logic;     -- Enable stage 1 of the pipeline
            EN2 :  in std_logic;     -- Enable stage 2 of the pipeline
            EN3 :  in std_logic;     -- Enable stage 3 of the pipeline
    
            -- Bus to DATA MEMORY
            DATAMEM_BUS_TOMEM:  out std_logic_vector(N_BIT_DATA - 1 downto 0); -- Data bus from the datapath to the data memory
            DATAMEM_BUS_FROMEM: in std_logic_vector(N_BIT_DATA - 1 downto 0); -- Data bus from the data memory to the datapath
            DATAMEM_ADDR:       out std_logic_vector(N_BIT_MEM_ADDR-1 downto 0); -- Address of the data memory
    
            --
            --          REGISTER FILE
            --
            RS1 :   in std_logic_vector(N_BIT_ADDR_RF-1 downto 0);      -- address PORT 1 of the register file
            RS2 :   in std_logic_vector(N_BIT_ADDR_RF-1 downto 0);      -- address PORT 2 of the register file
            WS1 :   in std_logic_vector(N_BIT_ADDR_RF-1 downto 0);      -- Address used for the write back
    
            -- Our RF has two reading port and one writing port
    
            RF1 :   in std_logic;     -- Read enable port 1 of the register file
            RF2 :   in std_logic;     -- Read enable port 2 of the register file 
            WF  :   in std_logic;     -- Write enable of the register file
        
            -- RF PROC MEMORY
            RF_BUS_TOMEM:  out std_logic_vector(N_BIT_DATA - 1 downto 0); -- Data bus from the datapath to the RF memory
            RF_BUS_FROMEM: in std_logic_vector(N_BIT_DATA - 1 downto 0); -- Data bus from the RF memory to the datapath
            RF_MEM_ADDR:   out std_logic_vector(N_BIT_RF_MEM_ADDR-1 downto 0); -- Address of the RF memory
            RF_MEM_RM:      out std_logic;
            RF_MEM_WM:      out std_logic; -- TODO: comments here
            
            -- Used to manage the procedure call
            CALL:       in std_logic;
            RET:        in std_logic;
            FILL:       out std_logic;
            SPILL:      out std_logic;
    
            -- Immediate value for the datapath 
            
            INP1:   in std_logic_vector(N_BIT_DATA - 1 downto 0); -- immediate 1
            INP2:   in std_logic_vector(N_BIT_DATA - 1 downto 0); -- immediate 2
            
            -- mux selector for ALU inputs
            S1: in std_logic; -- Selector for top mux, called mux A
            S2: in std_logic; -- Selector for bottom mux, called mux B
            
    
    
            -- ALU 
            ALU_OP: in std_logic_vector(N_OPSEL + 3 - 1 downto 0); -- Control signal for the ALU in order to decide the operation
            ALU_COUT: out std_logic;    -- Carry out of the operation made by the ALU
            A_LE_B: out std_logic;      -- A less equal B 
            A_LT_B: out std_logic;      -- A less than B
            A_GT_B: out std_logic;      -- A greater that B
            A_GE_B: out std_logic;      -- A greater equal B
            A_EQ_B: out std_logic;      -- A equal B
    
            -- Mux selector for stage 3 of the pipeline
            S3: in std_logic -- Selector for mux of stage 3
        );
    end component;

    type mem_t is array(0 to 2**10-1) of std_logic_vector(32-1 downto 0);
    type codemem_t is array(0 to 10) of std_logic_vector(9+ALU_ADD'length-1 downto 0);
    type imm_t is array(codemem_t'range) of std_logic_vector(31 downto 0);
    type rws_t is array(codemem_t'range) of std_logic_vector(4 downto 0);

    signal CLK: std_logic := '0';
    signal RST: std_logic;
    signal EN1, EN2, EN3, RF1, RF2, WF, CALL, RET, SPILL, FILL, S3, S2, S1, A_EQ_B, A_GE_B, A_GT_B, A_LT_B, A_LE_B, ALU_COUT, RF_MEM_RM, RF_MEM_WM: std_logic;
    signal ALU_OP: std_logic_vector(4 downto 0);
    signal DATAMEM_BUS_FROMEM, DATAMEM_BUS_TOMEM, RF_BUS_FROMEM, RF_BUS_TOMEM, INP2, INP1: std_logic_vector(31 downto 0);
    signal DATAMEM_ADDR, RF_MEM_ADDR: std_logic_vector(9 downto 0);
    signal WS1, RS1, RS2: std_logic_vector(4 downto 0);

    signal DATAMEM: mem_t := (others => (others => '1'));
    signal RFMEM: mem_t := (others => (others => '1'));

    signal codemem: codemem_t := (
        -- RF1, RF2, EN1, S1, S2, >ALUOP<, EN2, S3, WF, EN3
        "10101" & ALU_ADD & "1010", -- ADDI R2, R0, 0x3F
        "00000" & ALU_ADD & "0000", -- NOP
        "00000" & ALU_ADD & "0000", -- NOP
        "00000" & ALU_ADD & "0000", -- NOP
        "11100" & ALU_ADD & "1010", -- ADD R4, R2, R2
        "00000" & ALU_ADD & "0000", -- NOP
        "00000" & ALU_ADD & "0000", -- NOP
        "00000" & ALU_ADD & "0000", -- NOP
        "10101" & ALU_AND & "1010", -- ANDI R5, R4, 0xF0
        "00000" & ALU_ADD & "0000", -- NOP
        "00000" & ALU_ADD & "0000"  -- NOP
    );

    signal imm1: imm_t := (
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000"
    );

    signal imm2: imm_t := (
        x"0000003F",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"00000000",
        x"000000F0",
        x"00000000",
        x"00000000"
    );

    signal drs1: rws_t := (
        "00000",  
        "00000",  
        "00000",  
        "00000",  
        "00010",  
        "00000",  
        "00000",  
        "00000",  
        "00100",  
        "00000",  
        "00000" 
    );

    signal drs2: rws_t := (
        "00000",  
        "00000",  
        "00000",  
        "00000",  
        "00010",  
        "00000",  
        "00000",  
        "00000",  
        "00000",  
        "00000",  
        "00000"  
    );

    signal dws: rws_t := (
        "00010",  
        "00000",  
        "00000",  
        "00000",  
        "00100",  
        "00000",  
        "00000",  
        "00000",  
        "00101",  
        "00000",  
        "00000"
    );

begin

    DUT: DP generic map(
        N_BIT_DATA => 32,
        N_BIT_ADDR_RF => 5,
        N_OPSEL => 2,  
        N_BIT_MEM_ADDR => 10,    
        N_BIT_RF_MEM_ADDR => 10
    ) port map(
        Clk => CLK,
        Rst => RST,
        EN1 => EN1,
        EN2 => EN2,
        EN3 => EN3,
        DATAMEM_BUS_TOMEM => DATAMEM_BUS_TOMEM,
        DATAMEM_BUS_FROMEM => DATAMEM_BUS_FROMEM,
        DATAMEM_ADDR => DATAMEM_ADDR,
        RS1 => RS1,
        RS2 => RS2,
        WS1 => WS1,
        RF1 => RF1,
        RF2 => RF2,
        WF => WF,
        RF_BUS_TOMEM => RF_BUS_TOMEM,
        RF_BUS_FROMEM => RF_BUS_FROMEM,
        RF_MEM_ADDR => RF_MEM_ADDR,
        RF_MEM_RM => RF_MEM_RM,
        RF_MEM_WM => RF_MEM_WM,
        CALL => CALL,
        RET => RET,
        FILL => FILL, 
        SPILL => SPILL,
        INP1 => INP1, 
        INP2 => INP2,
        S1 => S1,
        S2 => S2,
        ALU_OP => ALU_OP,
        ALU_COUT => ALU_COUT,
        A_LE_B => A_LE_B,
        A_LT_B => A_LT_B,
        A_GT_B => A_GT_B,
        A_GE_B => A_GE_B,
        A_EQ_B => A_EQ_B,
        S3 => S3
    );

    process
    begin

        wait for 0.5 ns;
        clk <= not clk;
     
    end process;

    process
    begin

        wait until clk = '0';
        
        EN1 <= '0';
        EN2 <= '0';
        EN3 <= '0';
        RS1 <= (others => '0');
        RS2 <= (others => '0');
        WS1 <= (others => '0');
        RF1 <= '0';
        RF2 <= '0';
        WF <= '0';
        CALL <= '0';
        RET <= '0';
        INP1 <= (others => '0');
        INP2 <= (others => '0');
        S1 <= '0';
        S2 <= '0';
        S3 <= '0';
        ALU_OP <= ALU_ADD;

        wait until clk = '0';
        
        Rst <= '1';
        
        wait until clk = '1';
        wait until clk = '0';

        Rst <= '0';
        
        wait until clk = '1';
        
        
        for i in codemem'range loop

            wait until Clk = '0';


            RF1 <= codemem(i)(codemem(i)'length-1);
            RF2 <= codemem(i)(codemem(i)'length-2);
            EN1 <= codemem(i)(codemem(i)'length-3);
            INP1 <= imm1(i);
            INP2 <= imm2(i);
            RS1 <= drs1(i);
            RS2 <= drs2(i);
            WS1 <= dws(i);

            if (i > 0) then
                S1 <= codemem(i-1)(codemem(i-1)'length-4);
                S2 <= codemem(i-1)(codemem(i-1)'length-5);
                ALU_OP <= codemem(i-1)(codemem(i-1)'length-6 downto codemem(i-1)'length-6-ALU_ADD'length+1);
                EN2 <= codemem(i-1)(codemem(i-1)'length-11);
            end if;
            
            if (i > 1) then
                S3 <= codemem(i-2)(codemem(i-2)'length-12);
                WF <= codemem(i-2)(codemem(i-2)'length-13);
                EN3 <= codemem(i-2)(codemem(i-2)'length-14);
            end if;


            wait until Clk = '1';

        end loop;

        
        -- clk <= '0';
        
        -- Rst <= '1';
        -- wait for 0.5 ns;
        -- CLK <= '1';
        -- wait for 1 ns;
        
        -- clk <= '0';
        
        -- Rst <= '0';
        -- wait for 0.5 ns;
        -- CLK <= '1';
        -- wait for 1 ns;
        
        
        -- -- ADDI R2, R2, 0x3F
        -- clk <= '0';

        -- RF1 <= '0';
        -- RS1 <= "00000";

        -- RF2 <= '0';
        -- RS2 <= "00000";

        -- WS1 <= "00010";

        -- INP1 <= x"0000003F";
        -- INP2 <= x"00000000";
        
        -- EN1 <= '1';
        
        -- wait for 1 ns;

        -- clk <= '1';
        -- wait for 1 ns;

        -- clk <= '0';

        -- S1 <= '1';
        -- S2 <= '1';

        -- ALU_OP <= ALU_ADD;

        -- EN2 <= '1';
        
        -- wait for 1 ns;

        -- clk <= '1';
        -- wait for 1 ns;

        -- clk <= '0';

        -- EN3 <= '0';
        
        -- S3 <= '0';
        -- WF <= '1';

        -- wait for 1 ns;

        -- clk <= '1';
        -- wait for 1 ns;


        -- -- ADD R4, R2, R2
        -- clk <= '0';

        
        -- RF1 <= '1';
        -- RS1 <= "00010"; -- R2

        -- RF2 <= '1';
        -- RS2 <= "00010"; -- R2

        -- WS1 <= "00100"; -- R4

        -- INP1 <= x"00000000";
        -- INP2 <= x"00000000";
        
        -- EN1 <= '1';

        -- wait for 1 ns;

        -- clk <= '1';
        -- wait for 1 ns;

        -- clk <= '0';

        -- S1 <= '0';
        -- S2 <= '0';

        -- ALU_OP <= ALU_ADD;

        -- EN2 <= '1';
        
        -- wait for 1 ns;

        -- clk <= '1';
        -- wait for 1 ns;


        -- clk <= '0';

        -- EN3 <= '0';
        
        -- S3 <= '0';
        -- WF <= '1';

        -- wait for 1 ns;

        -- clk <= '1';
        -- wait for 1 ns;

        -- wait;


    end process;


end test;



