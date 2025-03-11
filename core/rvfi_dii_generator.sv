
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
//
// Copyright 2025 Capabilities Limited

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
    logic [CVA6Cfg.FETCH_ALIGN_BITS:0] fetch_offset;
    logic [CVA6Cfg.FETCH_WIDTH*2-1:0] fetch_buff;
    logic [CVA6Cfg.DIIIDLEN-1:0] dii_id;

    logic busy;
    logic flushing;
    logic [CVA6Cfg.VLEN-1:0] vaddr_buff;    // 1st cycle: 12 bit index is taken for lookup
    exception_t ex_buff;     // we've encountered an exception

    logic rsp_attempt;

    assign dreq_o.ready = !dreq_i.kill_s1 && dreq_i.req;

    always_ff @(negedge clk_i) begin
        $display("A new day dawns");
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            dii_id <= test_dii_start();
            fetch_buff <= '0;
            fetch_offset <= '0;
            flushing <= '0;
            rsp_attempt <= '0;
            dreq_o.ex <= '0;
            dreq_o.vaddr <= '0;
            busy <= '0;
        end else begin
            if (dreq_i.dii_flush) begin
                dii_id = dreq_i.dii_id;
                fetch_buff = 0;
                flushing = 1;
                $display("dii_flush, dii_id = %x", dii_id);
            end
            if (dreq_i.kill_s1) begin
                $display("kill_s1");
                busy <= '0;
                vaddr_buff <= 'h123123ab;
                rsp_attempt <= 1'b0;
            end else begin
                if (dreq_i.req) begin
                    $display("req. Addr = %x", dreq_i.vaddr);
                    busy <= 1;
                    vaddr_buff <= dreq_i.vaddr;
                    ex_buff <= dreq_i.ex;
                    if (flushing) begin
                        fetch_offset <= {1'b0, dreq_i.vaddr[CVA6Cfg.FETCH_ALIGN_BITS-1:0]};
                    end
                    flushing <= 0;
                end
                if (busy && !dreq_i.kill_s2) begin
                    automatic logic [31:0] instr;
                    automatic logic [2:0] instr_bytes;
                    automatic logic test_done;
                    rsp_attempt <= 1'b1;
                    dreq_o.ex <= ex_buff;
                    dreq_o.vaddr <= vaddr_buff;
                    fetch_buff = fetch_buff >> CVA6Cfg.FETCH_WIDTH;
                    fetch_offset = {1'b0, fetch_offset[CVA6Cfg.FETCH_ALIGN_BITS-1:0]};
                    $display("fetch_offset: ");
                    $display(fetch_offset);
                    $display("fetch_align_bits: ");
                    $display(CVA6Cfg.FETCH_ALIGN_BITS);
                    while (~fetch_offset[CVA6Cfg.FETCH_ALIGN_BITS]) begin
                        $display("Hello from always_ff");
                        $display(dii_id);
                        test_done = get_dii_cmd(dii_id) == 0;
                        if (test_done) begin
                            $display("test done");
                        end
                        instr = test_done ? 32'h13 : get_dii_insn(dii_id);
                        instr_bytes = instr[1:0] == 2'b11 ? 3'd4 : 3'd2;
                        fetch_buff = fetch_buff | (instr << (fetch_offset << 3));
                        fetch_offset = fetch_offset + instr_bytes;
                        dii_id = dii_id + (test_done ? 0 : 1);
                    end
                    dreq_o.data <= fetch_buff[CVA6Cfg.FETCH_WIDTH-1:0];
                    $display("%h", fetch_buff);
                end else begin
                    rsp_attempt <= 1'b0;
                end
            end
        end
    end

    assign dreq_o.valid = rsp_attempt & ~dreq_i.kill_s1;

endmodule
