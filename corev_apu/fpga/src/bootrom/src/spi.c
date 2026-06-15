// Copyright OpenHW Group contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "spi.h"
#include "uart.h"
#include "time.h"

void write_reg(uintptr_t addr, uint32_t value)
{
    volatile uint32_t *loc_addr = (volatile uint32_t *)addr;
    *loc_addr = value;
}

uint32_t read_reg(uintptr_t addr)
{
    return *(volatile uint32_t *)addr;
}

static inline void wait_for_reg_val(uintptr_t addr, uint32_t mask, uint32_t val)
{
    uint32_t status;
    do
    {
        status = read_reg(addr);
    } while ((status & mask) != val);
}

static inline void wait_for_tx_empty()
{
    wait_for_reg_val(SPI_STATUS_REG, SPI_STATUS_TX_EMPTY_MASK, SPI_STATUS_TX_EMPTY_MASK);
}

static inline void wait_for_rx_nonempty()
{
    wait_for_reg_val(SPI_STATUS_REG, SPI_STATUS_RX_EMPTY_MASK, 0);
}

void spi_init()
{
    print_uart("init SPI\r\n");

    // reset the axi quadspi core
    write_reg(SPI_RESET_REG, 0x0a);

    millisleep(1);

    write_reg(SPI_CONTROL_REG, 0x104);

    uint32_t status = read_reg(SPI_STATUS_REG);
    print_uart("status: 0x");
    print_uart_addr(status);
    print_uart("\r\n");

    // clear all fifos
    write_reg(SPI_CONTROL_REG, 0x166);

    status = read_reg(SPI_STATUS_REG);
    print_uart("status: 0x");
    print_uart_addr(status);
    print_uart("\r\n");

    write_reg(SPI_CONTROL_REG, 0x06);

    print_uart("SPI initialized!\r\n");
}

uint8_t spi_txrx(uint8_t byte)
{
    // enable slave select
    write_reg(SPI_SLAVE_SELECT_REG, 0xfffffffe);

    write_reg(SPI_TRANSMIT_REG, byte);

    wait_for_tx_empty();

    // enable spi control master flag
    write_reg(SPI_CONTROL_REG, 0x106);

    wait_for_rx_nonempty();

    uint32_t result = read_reg(SPI_RECEIVE_REG);

    if ((read_reg(SPI_STATUS_REG) & SPI_STATUS_RX_EMPTY_MASK) == 0)
    {
        print_uart("rx fifo not empty?? ");
        print_uart_addr(read_reg(SPI_STATUS_REG));
        print_uart("\r\n");
    }

    // disable slave select
    write_reg(SPI_SLAVE_SELECT_REG, 0xffffffff);

    // disable spi control master flag
    write_reg(SPI_CONTROL_REG, 0x06);

    return result;
}

int spi_write_bytes(uint8_t *bytes, uint32_t len, uint8_t *ret)
{
    if (len > 256) // FIFO maxdepth 256
        return -1;

    // enable slave select
    write_reg(SPI_SLAVE_SELECT_REG, 0xfffffffe);

    wait_for_tx_empty();

    for (int i = 0; i < len; i++)
    {
        write_reg(SPI_TRANSMIT_REG, bytes[i] & 0xff);
    }

    wait_for_tx_empty();

    // enable spi control master flag
    write_reg(SPI_CONTROL_REG, 0x106);

    for (int i = 0; i < len;)
    {
        wait_for_rx_nonempty();
        ret[i++] = read_reg(SPI_RECEIVE_REG);
    }

    // disable slave select
    write_reg(SPI_SLAVE_SELECT_REG, 0xffffffff);

    // disable spi control master flag
    write_reg(SPI_CONTROL_REG, 0x06);

    return 0;
}
