// Copyright 2026 Capabilities Limited.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions ansd limitations under the License.
//
// Author: Peter Rugg <peter.rugg@capabilitieslimited.co.uk>
//
// Date: 24.06.2026
// Description: CVA6 CHERI PCC checking unit

module cheri_pcc_check
  import cva6_cheri_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type exception_t = logic
) (
    input  logic                          clk_i,            // Clock
    input  logic                          rst_ni,           // Asynchronous reset active low
    input  logic       [CVA6Cfg.VLEN-1:0] pc_i,             // PC of instruction to check
    input  logic                          is_compressed_i,  // Instruction is compressed
    input  logic                          pcc_gen_i,        // PCC gen of instruction to check
    input  logic                          needs_asr_i,      // Instruction requires ASR
    input  cap_reg_t   [             1:0] pccs_i,           // Global PCCs live in the pipeline
    input  logic                          debug_mode_i,     // Debug mode: disable checks if high
    output exception_t                    pcc_ex_o          // Output exception
);

  cap_reg_t pcc;

  cap_meta_data_t pcc_meta;
  addrw_t pcc_base;
  addrwe_t pcc_top;
  logic pcc_bounds_root;
  logic [CVA6Cfg.VLEN-1:0] next_pc_off;
  logic [CVA6Cfg.VLEN-1:0] next_pc_addr;
  logic next_pc_carry;
  cap_tval2_t cheri_tval2;

  always_comb begin
    // Select correct pcc
    pcc = pccs_i[pcc_gen_i];
    // Extract PCC metadata
    pcc_meta = get_cap_reg_meta_data(pcc);
    pcc_base = get_cap_reg_base(pcc, pcc_meta);
    pcc_top = get_cap_reg_top(pcc, pcc_meta);
    pcc_bounds_root = are_cap_reg_bounds_root(pcc, pcc_meta);
    cheri_tval2.fault_type = CAP_INSTR_FETCH_FAULT;
    // Calculate next PC
    next_pc_off = {{CVA6Cfg.VLEN - 3{1'b0}}, is_compressed_i ? 3'h2 : 3'h4};
    {next_pc_carry, next_pc_addr} = {1'b0, pc_i} + {1'b0, next_pc_off};
  end

  always_comb begin
    automatic logic fault;
    fault = 1'b0;
    pcc_ex_o = '0;

    // Bounds check
    if ((addrw_t'(signed'(pc_i)) < pcc_base) ||
        ({1'b0, addrw_t'(signed'(next_pc_addr))} > pcc_top) ||
        (next_pc_carry && !pcc_bounds_root)) begin
      fault = 1'b1;
      cheri_tval2.fault_cause = CAP_BOUNDS_VIOLATION;
    end
    // ASR permission check
    if (needs_asr_i && !pcc.hperms.access_sys_regs) begin
      fault = 1'b1;
      cheri_tval2.fault_cause = CAP_PERM_VIOLATION;
    end
    // Execute permission check
    if (!pcc.hperms.permit_execute) begin
      fault = 1'b1;
      cheri_tval2.fault_cause = CAP_PERM_VIOLATION;
    end
    // Seal violation
    if (pcc.otype != UNSEALED_CAP) begin
      fault = 1'b1;
      cheri_tval2.fault_cause = CAP_SEAL_VIOLATION;
    end
    // Tag violation
    if (!pcc.tag) begin
      fault = 1'b1;
      cheri_tval2.fault_cause = CAP_TAG_VIOLATION;
    end
    if (fault) begin
      pcc_ex_o.cause = CAP_EXCEPTION;
      pcc_ex_o.tval2 = cheri_tval2;
      pcc_ex_o.valid = 1'b1;
    end

    // Disable exceptions for debug instructions
    if (debug_mode_i) pcc_ex_o.valid = 1'b0;
  end
endmodule
