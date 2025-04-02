
// Copyright 2025 Bruno Sá and Zero-Day Labs.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions ansd limitations under the License.
//
// Author: Bruno Sá <bruno.vilaca.sa@gmail.com>
// Acknowledges: Technology Inovation Institute (TII)
//
// Date: 01.01.2025
// Description: CVA6 RVFI DII Generator

`include "common_cells/registers.svh"

module rvfi_dii_generator
  import ariane_pkg::*;
  import wt_cache_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type icache_dreq_t = logic,
    parameter type icache_drsp_t = logic,
    parameter type exception_t = logic,
    parameter type rvfi_dii_inst_pack_t = logic
) (
    input logic clk_i,
    input logic rst_ni,
    // data requests
    input  icache_dreq_t dreq_i,
    output icache_drsp_t dreq_o,
    // refill port from Vengine
    input  logic         rvfi_dii_rtrn_vld_i,
    input  rvfi_dii_inst_pack_t rvfi_dii_inst_pack_i,
    output logic         rvfi_dii_data_ready_o
);
    logic [CVA6Cfg.PCLEN-1:0] vaddr_d, vaddr_q;
    exception_t ex_d, ex_q;
    logic busy_q, busy_d;
    assign vaddr_d = (~busy_q & dreq_i.req) ? dreq_i.vaddr : vaddr_q;
    assign ex_d    = (~busy_q & dreq_i.req) ? dreq_i.ex : ex_q;

    always_comb begin : inject_instr
        dreq_o.vaddr = vaddr_q;
        dreq_o.valid = 1'b0;
        dreq_o.ready = 1'b0;
        dreq_o.data  = rvfi_dii_inst_pack_i.rvfi_insn;
        rvfi_dii_data_ready_o = 1'b0;
        busy_d = busy_q;
        if (busy_q) begin
            rvfi_dii_data_ready_o = 1'b1;
            if (rvfi_dii_rtrn_vld_i) begin
                busy_d = 1'b0;
                dreq_o.valid = 1'b1;
            end
            // check for errors
            if ((dreq_i.kill_s1 || dreq_i.kill_s2) && !ex_q.valid) begin
                busy_d = 1'b0;
                rvfi_dii_data_ready_o = 1'b0;
                dreq_o.valid = 1'b0;
            end
        end else begin
            dreq_o.ready = 1'b1;
            if (dreq_i.req && !dreq_i.kill_s1 && !dreq_i.kill_s2)
                busy_d = 1'b1;
        end
    end

    if (CVA6Cfg.CheriPresent) begin : gen_cheri_pcc_checks
    always_comb begin
        automatic cva6_cheri_pkg::cap_tval_t cheri_tval;
        automatic cva6_cheri_pkg::cap_reg_t npcc;
        cva6_cheri_pkg::cap_meta_data_t npcc_meta_data;
        automatic cva6_cheri_pkg::addrw_t min_instr_off;
        automatic cva6_cheri_pkg::addrw_t fetch_pcc_base;
        automatic cva6_cheri_pkg::addrwe_t fetch_pcc_top;

        npcc = cva6_cheri_pkg::cap_mem_to_cap_reg(vaddr_q);
        npcc_meta_data = cva6_cheri_pkg::get_cap_reg_meta_data(npcc);
        fetch_pcc_base = cva6_cheri_pkg::get_cap_reg_base(npcc, npcc_meta_data);
        fetch_pcc_top = cva6_cheri_pkg::get_cap_reg_top(npcc, npcc_meta_data);

        // TODO-cheri(ninolomata): fix this once we disable compressed instructions without trigering errors
        min_instr_off = ((CVA6Cfg.RVC && !CVA6Cfg.RVFI_DII) ? {{CVA6Cfg.XLEN-2{1'b0}}, 2'h2} : {{CVA6Cfg.XLEN-3{1'b0}}, 3'h4});

        cheri_tval     = {CVA6Cfg.XLEN{1'b0}};
        dreq_o.ex.cause = cva6_cheri_pkg::CAP_EXCEPTION;
        dreq_o.ex.valid = 1'b0;
        dreq_o.ex.tval  = {CVA6Cfg.XLEN{1'b0}};
        dreq_o.ex.tval2 = {CVA6Cfg.XLEN{1'b0}};
        dreq_o.ex.tinst = {CVA6Cfg.XLEN{1'b0}};
        dreq_o.ex.gva   = 1'b0;

        if(!(fetch_pcc_base[0] == 1'b0)) begin
            cheri_tval.cause   = cva6_cheri_pkg::CAP_UNLIGNED_BASE;
            dreq_o.ex.valid     = 1'b1;
        end

        if(vaddr_q[CVA6Cfg.XLEN-1:0] < fetch_pcc_base || ($unsigned(vaddr_q[CVA6Cfg.XLEN-1:0]) + min_instr_off) > fetch_pcc_top) begin
            cheri_tval.cause   = cva6_cheri_pkg::CAP_LENGTH_VIOLATION;
            dreq_o.ex.valid     = 1'b1;
        end

        if(!npcc.hperms.permit_execute) begin
            cheri_tval.cause   = cva6_cheri_pkg::CAP_PERM_EXEC_VIOLATION;
            dreq_o.ex.valid     = 1'b1;
        end
        if((npcc.otype != cva6_cheri_pkg::UNSEALED_CAP) && npcc.tag) begin
            cheri_tval.cause = cva6_cheri_pkg::CAP_SEAL_VIOLATION;
            dreq_o.ex.valid     = 1'b1;
        end
        if(!npcc.tag) begin
            cheri_tval.cause = cva6_cheri_pkg::CAP_TAG_VIOLATION;
            dreq_o.ex.valid     = 1'b1;
        end
        // Update tval
        dreq_o.ex.tval = cheri_tval;
    end
    end

    `FFLARN(vaddr_q, vaddr_d, '1, '0, clk_i, rst_ni)
    `FFLARN(ex_q, ex_d, '1, '0, clk_i, rst_ni)
    `FFLARN(busy_q, busy_d, '1, '0, clk_i, rst_ni)

endmodule
