-- =============================================================================
-- File:                    neorv32_wb_gpio.vhdl
--
-- Authors:                 Niklaus Leuenberger <leuen4@bfh.ch>
--
-- Version:                 0.1
--
-- Entity:                  neorv32_wb_gpio
--
-- Description:             Wishbone wrapper for neorv32_gpio. Instead of
--                          accessing it through the neorv32 specific internal
--                          bus, this wraps it in Wishbone. Reason being to
--                          allow routing to this gpio through an external
--                          Wishbone interconnect (e.g. crossbar).
--
-- Note:                    This is possibly wrong (re / we) active for more
--                          than one cycle. But physical testing had no error.
--
-- Changes:                 0.1, 2023-04-16, leuen4
--                              initial version
-- =============================================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY neorv32;
USE neorv32.neorv32_package.ALL;

USE work.wb_pkg.ALL;

ENTITY neorv32_wb_gpio IS
    GENERIC (
        GPIO_NUM : NATURAL -- number of GPIO input/output pairs (0..64)
    );
    PORT (
        -- Global control --
        clk_i  : IN STD_ULOGIC; -- global clock, rising edge
        rstn_i : IN STD_ULOGIC; -- global reset, low-active, async

        -- Wishbone slave interface --
        wb_slave_i : IN wb_slave_rx_sig_t;  -- control and data from master to slave
        wb_slave_o : OUT wb_slave_tx_sig_t; -- status and data from slave to master

        -- parallel io --
        gpio_o : OUT STD_ULOGIC_VECTOR(63 DOWNTO 0);
        gpio_i : IN STD_ULOGIC_VECTOR(63 DOWNTO 0)
    );
END ENTITY neorv32_wb_gpio;

ARCHITECTURE no_target_specific OF neorv32_wb_gpio IS

    -- Signals of the neorv32 cpu internal bus.
    SIGNAL we : STD_ULOGIC; -- write request
    SIGNAL re : STD_ULOGIC; -- read request
    SIGNAL addr : STD_ULOGIC_VECTOR(31 DOWNTO 0); -- bus access address
    SIGNAL wdata : STD_ULOGIC_VECTOR(31 DOWNTO 0); -- bus write data
    SIGNAL rdata : STD_ULOGIC_VECTOR(31 DOWNTO 0); -- bus read data
    SIGNAL ack : STD_ULOGIC; -- bus transfer acknowledge

BEGIN

    -- Map Wishbone signals to neorv32 internal bus.
    we <= wb_slave_i.stb AND wb_slave_i.we;
    re <= wb_slave_i.stb AND NOT wb_slave_i.we;
    addr <= wb_slave_i.adr;
    wdata <= wb_slave_i.dat;
    wb_slave_o.dat <= rdata;
    wb_slave_o.ack <= ack;
    wb_slave_o.err <= '0'; -- no error possible

    -- NEORV32 GPIO instance ------------------------------------------------------------------
    -- -------------------------------------------------------------------------------------------
    neorv32_gpio_inst : neorv32_gpio
    GENERIC MAP(
        GPIO_NUM => GPIO_NUM -- number of GPIO input/output pairs (0..64)
    )
    PORT MAP(
        -- host access --
        clk_i  => clk_i,  -- global clock line
        rstn_i => rstn_i, -- global reset line, low-active, async
        addr_i => addr,   -- address
        rden_i => re,     -- read enable
        wren_i => we,     -- write enable
        data_i => wdata,  -- data in
        data_o => rdata,  -- data out
        ack_o  => ack,    -- transfer acknowledge
        -- parallel io --
        gpio_o => gpio_o,
        gpio_i => gpio_i
    );

END ARCHITECTURE no_target_specific;