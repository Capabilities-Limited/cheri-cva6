// Copyright 2023 Commissariat a l'Energie Atomique et aux Energies
//                Alternatives (CEA)
//
// Licensed under the Solderpad Hardware License, Version 2.1 (the “License”);
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Authors: Cesar Fuguet
// Date: February, 2023
// Description: AXI arbiter for the CVA6 cache subsystem integrating an
//              instruction cache and the Core-V High-Performance L1 Dcache
//              (CV-HPDcache). Both caches use the HPDcache memory interface
//              (the instruction cache is built on a read-only HPDcache): their
//              read requests are arbitrated, and the read responses (flits of
//              the AXI data width) are routed back by memory ID.

module cva6_hpdcache_subsystem_axi_arbiter
//  Parameters
//  {{{
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type hpdcache_mem_id_t = logic,
    parameter type hpdcache_mem_req_t = logic,
    parameter type hpdcache_mem_req_w_t = logic,
    parameter type hpdcache_mem_resp_r_t = logic,
    parameter type hpdcache_mem_resp_w_t = logic,
    //  memory IDs of the I$: [IcacheIdBase, IcacheIdBase + 2**IcacheIdWidth)
    parameter int unsigned IcacheIdBase = 0,
    parameter int unsigned IcacheIdWidth = 1,

    parameter int unsigned AxiAddrWidth = 1,
    parameter int unsigned AxiDataWidth = 1,
    parameter int unsigned AxiIdWidth = 1,
    parameter int unsigned AxiUserWidth = 1,
    parameter type axi_ar_chan_t = logic,
    parameter type axi_aw_chan_t = logic,
    parameter type axi_w_chan_t = logic,
    parameter type axi_b_chan_t = logic,
    parameter type axi_r_chan_t = logic,
    parameter type axi_req_t = logic,
    parameter type axi_rsp_t = logic
)
//  }}}

//  Ports
//  {{{
(
    input logic clk_i,
    input logic rst_ni,

    //  Interfaces from/to I$ (read only)
    //  {{{
    output logic              icache_read_ready_o,
    input  logic              icache_read_valid_i,
    input  hpdcache_mem_req_t icache_read_i,

    input  logic                 icache_read_resp_ready_i,
    output logic                 icache_read_resp_valid_o,
    output hpdcache_mem_resp_r_t icache_read_resp_o,
    //  }}}

    //  Interfaces from/to D$
    //  {{{
    //      Read interface
    output logic              dcache_read_ready_o,
    input  logic              dcache_read_valid_i,
    input  hpdcache_mem_req_t dcache_read_i,

    input  logic                 dcache_read_resp_ready_i,
    output logic                 dcache_read_resp_valid_o,
    output hpdcache_mem_resp_r_t dcache_read_resp_o,

    //      Write interface
    output logic              dcache_write_ready_o,
    input  logic              dcache_write_valid_i,
    input  hpdcache_mem_req_t dcache_write_i,

    output logic                dcache_write_data_ready_o,
    input  logic                dcache_write_data_valid_i,
    input  hpdcache_mem_req_w_t dcache_write_data_i,

    input  logic                 dcache_write_resp_ready_i,
    output logic                 dcache_write_resp_valid_o,
    output hpdcache_mem_resp_w_t dcache_write_resp_o,
    //  }}}

    //  AXI port to upstream memory/peripherals
    //  {{{
    output axi_req_t axi_req_o,
    input  axi_rsp_t axi_resp_i
    //  }}}
);
  //  }}}

  //  Internal type definitions
  //  {{{

  localparam int MEM_RESP_RT_DEPTH = (1 << CVA6Cfg.MEM_TID_WIDTH);
  typedef hpdcache_mem_id_t [MEM_RESP_RT_DEPTH-1:0] mem_resp_rt_t;
  //  }}}

  //  Read request arbiter
  //  {{{
  logic              [1:0] mem_req_read_ready;
  logic              [1:0] mem_req_read_valid;
  hpdcache_mem_req_t [1:0] mem_req_read;

  logic                    mem_req_read_ready_arb;
  logic                    mem_req_read_valid_arb;
  hpdcache_mem_req_t       mem_req_read_arb;

  assign icache_read_ready_o = mem_req_read_ready[0];
  assign mem_req_read_valid[0] = icache_read_valid_i;
  assign mem_req_read[0] = icache_read_i;

  assign dcache_read_ready_o = mem_req_read_ready[1];
  assign mem_req_read_valid[1] = dcache_read_valid_i;
  assign mem_req_read[1] = dcache_read_i;

  hpdcache_mem_req_read_arbiter #(
      .N                 (2),
      .hpdcache_mem_req_t(hpdcache_mem_req_t)
  ) i_mem_req_read_arbiter (
      .clk_i,
      .rst_ni,

      .mem_req_read_ready_o(mem_req_read_ready),
      .mem_req_read_valid_i(mem_req_read_valid),
      .mem_req_read_i      (mem_req_read),

      .mem_req_read_ready_i(mem_req_read_ready_arb),
      .mem_req_read_valid_o(mem_req_read_valid_arb),
      .mem_req_read_o      (mem_req_read_arb),

      .gnt_index_o(  /*open*/)
  );
  //  }}}

  //  Read response demultiplexor
  //  {{{
  logic                 mem_resp_read_ready;
  logic                 mem_resp_read_valid;
  hpdcache_mem_resp_r_t mem_resp_read;

  logic                 mem_resp_read_ready_arb[1:0];
  logic                 mem_resp_read_valid_arb[1:0];
  hpdcache_mem_resp_r_t mem_resp_read_arb      [1:0];

  mem_resp_rt_t         mem_resp_read_rt;

  always_comb begin
    for (int i = 0; i < MEM_RESP_RT_DEPTH; i++) begin
      mem_resp_read_rt[i] = ((i >= int'(IcacheIdBase)) &&
                             (i < int'(IcacheIdBase) + (1 << IcacheIdWidth))) ? 0 : 1;
    end
  end

  hpdcache_mem_resp_demux #(
      .N        (2),
      .resp_t   (hpdcache_mem_resp_r_t),
      .resp_id_t(hpdcache_mem_id_t)
  ) i_mem_resp_read_demux (
      .clk_i,
      .rst_ni,

      .mem_resp_ready_o(mem_resp_read_ready),
      .mem_resp_valid_i(mem_resp_read_valid),
      .mem_resp_id_i   (mem_resp_read.mem_resp_r_id),
      .mem_resp_i      (mem_resp_read),

      .mem_resp_ready_i(mem_resp_read_ready_arb),
      .mem_resp_valid_o(mem_resp_read_valid_arb),
      .mem_resp_o      (mem_resp_read_arb),

      .mem_resp_rt_i(mem_resp_read_rt)
  );

  assign icache_read_resp_valid_o = mem_resp_read_valid_arb[0];
  assign icache_read_resp_o = mem_resp_read_arb[0];
  assign mem_resp_read_ready_arb[0] = icache_read_resp_ready_i;

  assign dcache_read_resp_valid_o = mem_resp_read_valid_arb[1];
  assign dcache_read_resp_o = mem_resp_read_arb[1];
  assign mem_resp_read_ready_arb[1] = dcache_read_resp_ready_i;
  //  }}}

  //  AXI adapters
  //  {{{

  hpdcache_mem_to_axi_write #(
      .hpdcache_mem_req_t   (hpdcache_mem_req_t),
      .hpdcache_mem_req_w_t (hpdcache_mem_req_w_t),
      .hpdcache_mem_resp_w_t(hpdcache_mem_resp_w_t),
      .aw_chan_t            (axi_aw_chan_t),
      .w_chan_t             (axi_w_chan_t),
      .b_chan_t             (axi_b_chan_t),
      .userEn               (CVA6Cfg.CheriPresent)
  ) i_hpdcache_mem_to_axi_write (
      .req_ready_o(dcache_write_ready_o),
      .req_valid_i(dcache_write_valid_i),
      .req_i      (dcache_write_i),

      .req_data_ready_o(dcache_write_data_ready_o),
      .req_data_valid_i(dcache_write_data_valid_i),
      .req_data_i      (dcache_write_data_i),

      .resp_ready_i(dcache_write_resp_ready_i),
      .resp_valid_o(dcache_write_resp_valid_o),
      .resp_o      (dcache_write_resp_o),

      .axi_aw_valid_o(axi_req_o.aw_valid),
      .axi_aw_o      (axi_req_o.aw),
      .axi_aw_ready_i(axi_resp_i.aw_ready),

      .axi_w_valid_o(axi_req_o.w_valid),
      .axi_w_o      (axi_req_o.w),
      .axi_w_ready_i(axi_resp_i.w_ready),

      .axi_b_valid_i(axi_resp_i.b_valid),
      .axi_b_i      (axi_resp_i.b),
      .axi_b_ready_o(axi_req_o.b_ready)
  );

  hpdcache_mem_to_axi_read #(
      .hpdcache_mem_req_t   (hpdcache_mem_req_t),
      .hpdcache_mem_resp_r_t(hpdcache_mem_resp_r_t),
      .ar_chan_t            (axi_ar_chan_t),
      .r_chan_t             (axi_r_chan_t),
      .userEn               (CVA6Cfg.CheriPresent)
  ) i_hpdcache_mem_to_axi_read (
      .req_ready_o(mem_req_read_ready_arb),
      .req_valid_i(mem_req_read_valid_arb),
      .req_i      (mem_req_read_arb),

      .resp_ready_i(mem_resp_read_ready),
      .resp_valid_o(mem_resp_read_valid),
      .resp_o      (mem_resp_read),

      .axi_ar_valid_o(axi_req_o.ar_valid),
      .axi_ar_o      (axi_req_o.ar),
      .axi_ar_ready_i(axi_resp_i.ar_ready),

      .axi_r_valid_i(axi_resp_i.r_valid),
      .axi_r_i      (axi_resp_i.r),
      .axi_r_ready_o(axi_req_o.r_ready)
  );

  //  }}}

  //  Assertions
  //  {{{
  //  pragma translate_off
  initial
    assert (CVA6Cfg.MEM_TID_WIDTH <= AxiIdWidth)
    else $fatal(1, "MEM_TID_WIDTH shall be less or equal to AxiIdWidth");
  initial
    assert (CVA6Cfg.AxiDataWidth <= CVA6Cfg.ICACHE_LINE_WIDTH)
    else $fatal(1, "AxiDataWidth shall be less or equal to the width of a Icache line");
  initial
    assert (CVA6Cfg.AxiDataWidth <= CVA6Cfg.DCACHE_LINE_WIDTH)
    else $fatal(1, "AxiDataWidth shall be less or equal to the width of a Dcache line");
  //  pragma translate_on
  //  }}}

endmodule : cva6_hpdcache_subsystem_axi_arbiter
