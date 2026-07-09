// Copyright 2025 Capabilities Limited.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//

module branch_unit_coverage import ariane_pkg::*; #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type bp_resolve_t = logic,
    parameter type branchpredict_sbe_t = logic,
    parameter type exception_t = logic,
    parameter type fu_data_t = logic
) (
    input logic clk_i,
    input logic rst_ni,
    input logic v_i,
    input logic debug_mode_i,
    input fu_data_t fu_data_i,
    input logic [CVA6Cfg.PCLEN-1:0] pc_i,
    input logic [CVA6Cfg.DIIIDLEN-1:0] dii_id_i,
    input logic is_zcmt_i,
    input logic is_compressed_instr_i,
    input logic branch_valid_i,
    input logic branch_comp_res_i,
    output logic [CVA6Cfg.REGLEN-1:0] branch_result_o,
    input branchpredict_sbe_t branch_predict_i,
    output bp_resolve_t resolved_branch_o,
    output logic resolve_branch_o,
    output exception_t branch_exception_o
);
  covergroup cg_branch_unit_cap_ex @(posedge clk_i iff (branch_exception_o.valid && rst_ni));
    option.per_instance = 1;
    option.name = "cg_branch_unit_cap_ex";
    option.comment = "Every type of CHERI branch exception is thrown";
    option.detect_overlap = 1;

    cp_branch_ex_cause : coverpoint branch_exception_o.tval2[3:0] {
      bins TAG = {4'd0};
      bins SEAL = {4'd1};
      bins PERM = {4'd2};
      // INVALID ADDRESS exceptions not supported on CVA6
      bins BOUNDS = {4'd4};
    };
  endgroup

  covergroup cg_branch_unit_outcomes @(posedge clk_i iff (resolved_branch_o.valid && rst_ni));
    option.per_instance = 1;
    option.name = "cg_branch_unit_outcomes";
    option.comment = "All branch types resolved";
    option.detect_overlap = 1;

    cp_branch_mispredict : coverpoint resolved_branch_o.is_mispredict {
      bins NO_MISPRED = {1'b0};
      bins MISPRED = {1'b1};
    };

    cp_branch_cftype : coverpoint resolved_branch_o.cf_type {
      bins NoCF = {NoCF}; // TODO may be unreachable?
      bins Branch = {Branch};
      bins Jump = {Jump};
      bins JumpR = {JumpR};
      bins Return = {Return};
    };

    cp_branch_taken : coverpoint resolved_branch_o.is_taken {
      bins UNTAKEN = {1'b0};
      bins TAKEN = {1'b1};
    };

    cp_branch_pcc_change : coverpoint resolved_branch_o.is_pcc_change {
      bins PCC_NOCHANGE = {1'b0};
      bins PCC_CHANGE = {1'b1};
    };

  endgroup

  covergroup cg_branch_unit_inputs @(posedge clk_i iff (rst_ni && branch_valid_i));
    option.per_instance = 1;
    option.name = "cg_branch_unit_inputs";
    option.comment = "All branch operations attempted";
    option.detect_overlap = 1;

    cp_branch_op : coverpoint fu_data_i.operation {
      bins JALR = {JALR};
      bins CJALR = {CJALR};
      bins JAL = {JAL};
      bins CJAL = {CJAL};
      bins BEQ = {EQ};
      bins BNE = {NE};
      bins BLTS = {LTS};
      bins BGES = {GES};
      bins BLTU = {LTU};
      bins BGEU = {GEU};
    };

    cp_branch_predict : coverpoint branch_predict_i.cf {
      bins NoCF = {NoCF};
      bins Branch = {Branch};
      bins Jump = {Jump};
      bins JumpR = {JumpR};
      bins Return = {Return};
    };

    cp_branch_comp_res : coverpoint branch_comp_res_i {
      bins comp_untaken = {1'b0};
      bins comp_taken = {1'b1};
    };

    cp_branch_opa_tag : coverpoint cva6_cheri_pkg::is_cap_reg_valid(fu_data_i.operand_a) {
      bins Tagged = {1'b1};
      bins Untagged = {1'b0};
    }
  endgroup

  //===========================================================================
  // Instantiation
  //===========================================================================

  cg_branch_unit_cap_ex branch_unit_cap_ex_cov;
  cg_branch_unit_outcomes branch_unit_outcomes_cov;
  cg_branch_unit_inputs branch_unit_inputs_cov;

  initial begin
    branch_unit_cap_ex_cov = new();
    branch_unit_outcomes_cov = new();
    branch_unit_inputs_cov = new();

    $display("Branch unit coverage added");
  end

endmodule
