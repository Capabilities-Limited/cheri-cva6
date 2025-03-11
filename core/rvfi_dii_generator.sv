
// Copyright 2025 Bruno Sá and Zero-Day Labs.
// Copyright 2025 Capabilities Limited.
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
//

import "DPI-C" function byte get_dii_cmd(int idx);
import "DPI-C" function int get_dii_insn(int idx);
import "DPI-C" function int test_dii_start();

`include "common_cells/registers.svh"

module rvfi_dii_generator
  import ariane_pkg::*;
  import wt_cache_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type icache_dreq_t = logic,
    parameter type icache_drsp_t = logic,
    parameter type exception_t = logic
) (
    input logic clk_i,
    input logic rst_ni,
    // data requests
    input  icache_dreq_t dreq_i,
    output icache_drsp_t dreq_o
);
    logic [CVA6Cfg.FETCH_ALIGN_BITS:0] fetch_offset_q, fetch_offset_d;
    logic [CVA6Cfg.FETCH_WIDTH*2-1:0] fetch_buff_q, fetch_buff_d;
    logic [CVA6Cfg.DIIIDLEN-1:0] dii_id_q, dii_id_d;
    logic busy;
    logic flushing;
    logic [CVA6Cfg.VLEN-1:0] vaddr_buff;
    exception_t ex_buff;

    logic [CVA6Cfg.FETCH_WIDTH*2-1:0] instr; // Wider than needed to be shifted in
    logic [2:0] instr_bytes;
    logic test_done;
    always_comb begin
        dii_id_d = dii_id_q;
        fetch_offset_d = fetch_offset_q;
        fetch_buff_d = fetch_buff_q;
        instr = '0;
        instr_bytes = '0;
        test_done = '0;
        if (busy && !dreq_i.kill_s2) begin
            // Assume the pipeline consumed the full buffer
            fetch_offset_d = {1'b0, fetch_offset_d[CVA6Cfg.FETCH_ALIGN_BITS-1:0]};
            fetch_buff_d = fetch_buff_d >> CVA6Cfg.FETCH_WIDTH;
            // Shift the rest of the buffer into the requested slot
            fetch_offset_d = fetch_offset_d + vaddr_buff[CVA6Cfg.FETCH_ALIGN_BITS-1:0];
            fetch_buff_d = fetch_buff_d << {vaddr_buff[CVA6Cfg.FETCH_ALIGN_BITS-1:0], 3'b0};
            while (~fetch_offset_d[CVA6Cfg.FETCH_ALIGN_BITS] & (~fetch_offset_d[CVA6Cfg.FETCH_ALIGN_BITS-1:0] != 0)) begin
                test_done = get_dii_cmd(dii_id_d) == 0;
                instr = test_done ? 32'h13 : get_dii_insn(dii_id_d);
                instr_bytes = instr[1:0] == 2'b11 ? 3'd4 : 3'd2;
                fetch_buff_d = fetch_buff_d | (instr << ({fetch_offset_d, 3'b0}));
                fetch_offset_d = fetch_offset_d + instr_bytes;
                dii_id_d = dii_id_d + (test_done ? 0 : 1);
            end
            dreq_o.valid = 1'b1;
        end else begin
            dreq_o.valid = 1'b0;
        end
        dreq_o.ex = ex_buff;
        dreq_o.vaddr = vaddr_buff;
        dreq_o.data = fetch_buff_d;
        dreq_o.user = '0;
        dreq_o.ready = !dreq_i.kill_s1 && !dreq_i.kill_s2 && dreq_i.req;
        dreq_o.dii_id = dii_id_q;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            dii_id_q <= test_dii_start();
            fetch_buff_q <= '0;
            fetch_offset_q <= '0;
            flushing <= '0;
            busy <= '0;
        end else begin
            if (dreq_i.kill_s1 || dreq_i.kill_s2) begin
                fetch_buff_q <= '0;
                fetch_offset_q <= '0;
                flushing <= 1;
                busy <= '0;
            end else begin
                dii_id_q <= dii_id_d;
                fetch_buff_q <= fetch_buff_d;
                fetch_offset_q <= fetch_offset_d;
                if (dreq_i.req) begin
                    busy <= 1;
                    vaddr_buff <= dreq_i.vaddr;
                    ex_buff <= dreq_i.ex;
                    if (flushing) begin
                        dii_id_q <= dreq_i.dii_id;
                    end
                    flushing <= 0;
                end else begin
                    busy <= 0;
                end
            end
        end
    end
endmodule
