-- =============================================================================
-- File:                    wb_riscv_clint.vhdl
--
-- Authors:                 Niklaus Leuenberger <leuen4@bfh.ch>
--
-- Version:                 0.1
--
-- Entity:                  wb_riscv_clint
--
-- Description:             Core Local Interruptor (CLINT) for symmetric
--                          multiprocessor systems. Implements memory mapped
--                          registers for software and timer interrupts on a per
--                          HART basis.
--
-- Note:                    This CLINT may not be correct. It is based on the
--                          usage in FreeRTOS and the definitions of SiFive.
--                          Sometimes the CLINT is intertwined with the Core
--                          Level Interrupt Controller (CLIC), the Platform
--                          Level Interrupt Controller (PLIC) or also the
--                          Advanced Interrupt Architecture (AIA). But its hard
--                          to keep track of these unratified RISC-V extensions.
--
-- Note 2:                  Memory Layout:
--                           BASE + 0x0000: MSIP, HART 0, word
--                           BASE + 0x0004: MSIP, HART 1, word
--                           ...
--                           BASE + 0x3ff8: MSIP, HART 4094, word
--                           BASE + 0x3ffc: reserved
--                           BASE + 0x4000: MTIMECMP, HART 0, double word
--                           BASE + 0x4008: MTIMECMP, HART 1, double word
--                           ...
--                           BASE + 0xbff0: MTIMECMP, HART 4094, double word
--                           BASE + 0xbff8: MTIME, double word
--
-- Changes:                 0.1, 2023-08-21, leuen4
--                              initial version
-- =============================================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;

USE work.wb_pkg.ALL;

ENTITY wb_riscv_clint IS
    GENERIC (
        N_HARTS : POSITIVE := 1 -- number of HARTs (1 to 4095)
    );
    PORT (
        -- Global control --
        clk_i  : IN STD_ULOGIC; -- global clock, rising edge
        rstn_i : IN STD_ULOGIC; -- global reset, low-active, asyn
        -- Wishbone slave interface --
        wb_slave_i : IN wb_req_sig_t;
        wb_slave_o : OUT wb_resp_sig_t;
        -- IRQs --
        mtime_irq_o : OUT STD_ULOGIC_VECTOR(N_HARTS - 1 DOWNTO 0); -- machine timer interrupt
        msw_irq_o   : OUT STD_ULOGIC_VECTOR(N_HARTS - 1 DOWNTO 0)  -- machine software interrupt
    );
END ENTITY wb_riscv_clint;

ARCHITECTURE no_target_specific OF wb_riscv_clint IS

    -- memory mapped registers
    SIGNAL msip_regs : STD_ULOGIC_VECTOR(N_HARTS - 1 DOWNTO 0) := (OTHERS => '0'); -- software interrupt
    TYPE mtimecmp_regs_t IS ARRAY (NATURAL RANGE <>) OF UNSIGNED(63 DOWNTO 0);
    SIGNAL mtimecmp_regs : mtimecmp_regs_t(N_HARTS - 1 DOWNTO 0); -- timer compare
    SIGNAL mtime_reg : UNSIGNED(63 DOWNTO 0) := (OTHERS => '0'); -- hardware timer

BEGIN

    -- Access to registers.
    reg_access : PROCESS (clk_i) IS
        VARIABLE msip_hart_id : INTEGER RANGE 0 TO N_HARTS - 1;
        VARIABLE mtimecmp_hart_id : INTEGER RANGE 0 TO N_HARTS - 1;
    BEGIN
        IF rising_edge(clk_i) THEN
            IF rstn_i = '0' THEN
                msip_regs <= (OTHERS => '0');
                mtimecmp_regs <= (OTHERS => (OTHERS => '0'));
                wb_slave_o.ack <= '0';
                wb_slave_o.err <= '0';
            ELSIF wb_slave_i.stb = '1' THEN
                IF wb_slave_i.adr(15 DOWNTO 14) = "00" THEN
                    -- Access to msip registers, offset 0x0000 - 0x3ffc.
                    msip_hart_id := to_integer(UNSIGNED(wb_slave_i.adr(13 DOWNTO 2)));
                    IF wb_slave_i.we = '1' THEN
                        msip_regs(msip_hart_id) <= wb_slave_i.dat(0);
                    ELSE
                        wb_slave_o.dat <= x"0000000" & "000" & msip_regs(msip_hart_id);
                    END IF;
                ELSIF wb_slave_i.adr(15 DOWNTO 3) = "1011111111111" THEN
                    -- Access to mtime register, offset 0xbff8.
                    IF wb_slave_i.we = '1' THEN
                        -- ToDo: write access
                    ELSE
                        IF wb_slave_i.adr(2) = '0' THEN -- lower word
                            wb_slave_o.dat <= STD_ULOGIC_VECTOR(mtime_reg(31 DOWNTO 0));
                        ELSE -- upper word
                            wb_slave_o.dat <= STD_ULOGIC_VECTOR(mtime_reg(63 DOWNTO 32));
                        END IF;
                    END IF;
                ELSE
                    -- Access to mtimecmp registers, offset 0x4000 - 0xbff0.
                    mtimecmp_hart_id := to_integer(UNSIGNED(wb_slave_i.adr(13 DOWNTO 3)));
                    IF wb_slave_i.we = '1' THEN
                        IF wb_slave_i.adr(2) = '0' THEN -- lower word
                            mtimecmp_regs(mtimecmp_hart_id)(31 DOWNTO 0) <= UNSIGNED(wb_slave_i.dat);
                        ELSE -- upper word
                            mtimecmp_regs(mtimecmp_hart_id)(63 DOWNTO 32) <= UNSIGNED(wb_slave_i.dat);
                        END IF;
                    ELSE
                        IF wb_slave_i.adr(2) = '0' THEN -- lower word
                            wb_slave_o.dat <= STD_ULOGIC_VECTOR(mtimecmp_regs(mtimecmp_hart_id)(31 DOWNTO 0));
                        ELSE -- upper word
                            wb_slave_o.dat <= STD_ULOGIC_VECTOR(mtimecmp_regs(mtimecmp_hart_id)(63 DOWNTO 32));
                        END IF;
                    END IF;
                END IF;
            END IF;
            -- Acknowledge every slave access and generate no errors.
            -- ToDo: Generate error for non implemented harts.
            wb_slave_o.ack <= wb_slave_i.stb;
            wb_slave_o.err <= '0';
        END IF;
    END PROCESS reg_access;

    -- Machine Timer, monotonically increasing with each clock tick.
    mtime_proc : PROCESS (clk_i) IS
    BEGIN
        IF rising_edge(clk_i) THEN
            IF rstn_i = '0' THEN
                mtime_reg <= (OTHERS => '0');
            ELSE
                mtime_reg <= mtime_reg + 1;
            END IF;
        END IF;
    END PROCESS mtime_proc;

    -- interrupt outputs
    msw_irq_o <= msip_regs;
    time_comparator : FOR i IN N_HARTS - 1 DOWNTO 0 GENERATE
        mtime_irq_o(i) <= '1' WHEN mtime_reg >= mtimecmp_regs(i) ELSE
        '0';
    END GENERATE;

END ARCHITECTURE no_target_specific;
