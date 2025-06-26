// Copyright 2022 Bruno Sá and Zero-Day Labs.
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
// Description: CVA6 CHERI Logic Unit


module cheri_unit import ariane_pkg::*; import cva6_cheri_pkg::*;#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg       = config_pkg::cva6_cfg_empty,
    parameter type fu_data_t = logic,
    parameter type exception_t = logic,
    parameter int CHERI_ISA_V8       = 0
    ) (
    input  logic                     clk_i,         // Clock
    input  logic                     rst_ni,        // Asynchronous reset active low
    input  logic                     v_i ,
    input  fu_data_t                 fu_data_i,
    input  cap_pcc_t                 pcc_i,          // Current PCC
    input  cap_reg_t                 ddc_i,          // Current DDC
    input  logic                     clu_valid_i,
    input  addrw_t                   alu_result_i,
    output cap_reg_t                 clu_result_o   // Return resulting cap
);
    // operand a decode fields
    cap_reg_t operand_a;
    addrw_t operand_a_base;
    addrwe_t operand_a_top;
    addrw_t operand_a_length;
    addrw_t operand_a_address;
    logic operand_a_is_sealed;
    cap_meta_data_t op_a_meta_info;
    logic operand_a_hperms_malformed;
    logic operand_a_bounds_malformed;

    // operand b decode fields
    cap_reg_t operand_b;
    addrw_t operand_b_base;
    addrwe_t operand_b_top;
    //addrw_t operand_b_length;
    addrw_t operand_b_address;
    //addrw_t operand_b_offset;
    logic operand_b_is_sealed;
    cap_meta_data_t op_b_meta_info;
    logic operand_b_hperms_malformed;
    logic operand_b_bounds_malformed;

    // operand pcc decode meta data
    cap_reg_t      pcc;
    cap_meta_data_t op_pc_meta_info;

    // Common operations signals
    // Set address operations signals
    addrw_t address;
    cap_reg_t op_set_addr;
    cap_meta_data_t op_meta_set_addr;
    cap_reg_t res_set_addr;
    // Operation set/inc offset signals
    cap_reg_t op_set_offset;
    cap_meta_data_t op_meta_set_offset;
    bool_t set_offset;
    addrw_t   offset;
    cap_reg_t res_set_offset;
    // Operation set bounds;
    addrw_t set_bounds_len;
    cap_reg_t op_set_bounds;
    cap_reg_set_bounds_ret_t res_set_bounds;

    // Tag-clearing check signals
    localparam CAP_CHECK_NUM = 3;
    localparam TAG_CHECK_IDX = 0;
    localparam SEAL_CHECK_IDX = 1;
    localparam BOUNDS_CHECK_IDX = 2;
    logic [CAP_CHECK_NUM-1:0] operand_a_violations;
    logic [CAP_CHECK_NUM-1:0] operand_b_violations;
    logic [CAP_CHECK_NUM-1:0] check_operand_a_violations;
    logic [CAP_CHECK_NUM-1:0] check_operand_b_violations;
    logic en_ex;

    // Output signals
    cap_reg_t clu_result;

    assign pcc = cap_pcc_to_cap_reg(pcc_i);
    // -----------
    // CHERI ALU main logic circuit
    // -----------
    capw_t cap_mem;
    cap_mem_t cap_mem_null;
    cap_reg_t tmp_cap, req_cap;
    addrwe_t tmp_length;
    always_comb begin
        // exceptions signals reset
        check_operand_a_violations = {CAP_CHECK_NUM{1'b0}};
        check_operand_b_violations = {CAP_CHECK_NUM{1'b0}};

        // Set address operation reset signals
        op_set_addr                = operand_a;
        op_meta_set_addr           = op_a_meta_info;
        address                    = '{default:0};

        // Set offset operation reset signals
        op_set_offset              = operand_a;
        op_meta_set_offset         = op_a_meta_info;
        set_offset                 = 1'b0;
        offset                     = '{default:0};

        // Set bounds operation reset signals
        op_set_bounds              = operand_a;
        set_bounds_len             = (fu_data_i.operation == ariane_pkg::SCBNDSI) ? fu_data_i.imm : $unsigned(operand_b_address);

        // Output reset values
        clu_result                 = REG_NULL_CAP;

        // Auxiliar signals
        tmp_cap                    = REG_NULL_CAP;
        cap_mem                    = '0;
        cap_mem_null               = MEM_NULL_CAP;
        tmp_length                 = '0;

        unique case (fu_data_i.operation)
            // AUIPCC
            // TODO:change this to offset maybe
            ariane_pkg::AUIPCC: begin
                address          = alu_result_i;
                op_set_addr      = pcc;
                op_meta_set_addr = op_pc_meta_info;
                clu_result       = res_set_addr;
            end
            // CAndPerm
            ariane_pkg::ACPERM: begin
                check_operand_a_violations = (1 << SEAL_CHECK_IDX);
                tmp_cap = operand_a;
                tmp_cap.uperms = (tmp_cap.uperms & (operand_b_address[CAP_UPERMS_WIDTH+CAP_UPERMS_SHIFT-1:CAP_UPERMS_SHIFT]));
                tmp_cap.hperms = cap_hperms_t'(tmp_cap.hperms & report_perms_to_hperms(operand_b_address));
                clu_result = tmp_cap;
            end
            // CTestSubset
            ariane_pkg::CBLD,ariane_pkg::SCSS: begin
                tmp_cap = operand_b;
                tmp_cap.tag = 1'b1;
                if (fu_data_i.operation == ariane_pkg::SCSS) begin
                    if(operand_a.tag != operand_b.tag) begin
                        tmp_cap.tag = 1'b0;
                    end
                end else begin // CBLD
                    if(!operand_a.tag) begin
                        tmp_cap.tag = 1'b0;
                    end
                    if(operand_a_is_sealed) begin
                        tmp_cap.tag = 1'b0;
                    end
                end
                if(operand_b_base < operand_a_base) begin
                    tmp_cap.tag = 1'b0;
                end
                if(operand_b_top > operand_a_top) begin
                    tmp_cap.tag = 1'b0;
                end
                if((operand_a.uperms & operand_b.uperms) != operand_b.uperms) begin
                    tmp_cap.tag = 1'b0;
                end
                if((operand_a.hperms & operand_b.hperms) != operand_b.hperms) begin
                    tmp_cap.tag = 1'b0;
                end
                if(operand_a_bounds_malformed | operand_b_bounds_malformed) begin
                    tmp_cap.tag = 1'b0;
                end
                if(operand_a_hperms_malformed | operand_b_hperms_malformed) begin
                    tmp_cap.tag = 1'b0;
                end
                if(operand_a.res_lo != 0 | operand_a.res_hi != 0 | operand_b.res_lo != 0 | operand_b.res_hi != 0) begin
                    tmp_cap.tag = 1'b0;
                end
                if (fu_data_i.operation == ariane_pkg::CBLD) clu_result = tmp_cap;
                // fu_data_i.operation == ariane_pkg::SCSS
                else clu_result = set_cap_reg_addr(REG_NULL_CAP, {{CVA6Cfg.XLEN-1{1'b0}}, tmp_cap.tag});
            end
            // CGetBase
            ariane_pkg::GCBASE: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, operand_a_bounds_malformed ? '0 : operand_a_base);
            end
            // CGetFlags
            ariane_pkg::GCMODE: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, {{CVA6Cfg.XLEN-1{1'b0}},get_cap_reg_flags(operand_a)});
            end
            // CGetLength
            ariane_pkg::GCLEN: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, operand_a_bounds_malformed ? '0 : operand_a_length);
            end
            // CGetHigh
            ariane_pkg::GCHI: begin
                cap_mem = cap_reg_to_cap_mem(operand_a);
                clu_result = set_cap_reg_addr(REG_NULL_CAP, cap_mem[((CVA6Cfg.XLEN * 2) - 1):CVA6Cfg.XLEN]);
            end
            // CGetPerm
            ariane_pkg::GCPERM: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, {{CVA6Cfg.XLEN-19{1'b0}},
                                      hperms_and_uperms_to_report_perms(operand_a.hperms, operand_a.uperms)
                                    });
            end
            // CGetTag
            ariane_pkg::GCTAG: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, {{CVA6Cfg.XLEN-1{1'b0}},operand_a.tag});
            end
            // CGetType
            ariane_pkg::GCTYPE: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, {{CVA6Cfg.XLEN-1{1'b0}},operand_a.otype});
            end
            // CIncOffset and CIncOffsetImm
            // TODO-cheri(ninolomata): use ALU to calculate address
            ariane_pkg::CADD,ariane_pkg::CADDI: begin
                check_operand_a_violations = (1 << SEAL_CHECK_IDX);
                offset = operand_b_address;
                op_set_offset = operand_a;
                op_meta_set_offset = op_a_meta_info;
                set_offset = 1'b0;
                offset = ((fu_data_i.operation == ariane_pkg::CADD) ? operand_b_address : fu_data_i.imm);
                address = operand_a_address + offset;
                tmp_cap = res_set_offset;
                clu_result = tmp_cap;
            end
            // CMV
            ariane_pkg::CMV: begin
                clu_result = operand_a;
            end
            // CSealEntry
            ariane_pkg::SENTRY: begin
                clu_result = operand_a;
                check_operand_a_violations = (1 << SEAL_CHECK_IDX);
                clu_result.otype = SENTRY_CAP;
            end
            // CSetAddr
            ariane_pkg::SCADDR: begin
                en_ex =  1'b0;
                check_operand_a_violations = (1 << SEAL_CHECK_IDX);
                op_set_addr  = operand_a;
                op_meta_set_addr = op_a_meta_info;
                address      = operand_b.addr;
                clu_result = res_set_addr;
            end
            // CSetBounds, CSetBoundsExact, CSetBoundsImm,
            // CRepresentableAlignmentMask
            ariane_pkg::SCBNDSR,
            ariane_pkg::SCBNDS,
            ariane_pkg::SCBNDSI,
            ariane_pkg::CRAM: begin
                check_operand_a_violations = (1 << TAG_CHECK_IDX)    |
                                             (1 << BOUNDS_CHECK_IDX) |
                                             (1 << SEAL_CHECK_IDX);
                if (fu_data_i.operation == ariane_pkg::CRAM)
                    clu_result = set_cap_reg_addr(REG_NULL_CAP, res_set_bounds.mask);
                else
                    clu_result = res_set_bounds.cap;
                    
                // If the result is inexact, and needed to be
                if ((!res_set_bounds.exact && fu_data_i.operation == ariane_pkg::SCBNDS))
                    clu_result.tag = 1'b0;
            end
            // CSetEqualExact
            ariane_pkg::SCEQ: begin
                clu_result = set_cap_reg_addr(REG_NULL_CAP, {{CVA6Cfg.XLEN-1{1'b0}}, (cap_reg_to_cap_mem(operand_a) == cap_reg_to_cap_mem(operand_b)) ? 1'b1 : 1'b0});
            end
            // CSetFlags
            ariane_pkg::SCMODE: begin
                check_operand_a_violations = (1 << SEAL_CHECK_IDX);
                clu_result = (operand_a_hperms_malformed) ? operand_a : set_cap_reg_flags(operand_a, operand_b.addr[0]);
            end
            // CSetHigh
            ariane_pkg::SCHI: begin
                cap_mem = cap_reg_to_cap_mem(operand_a);
                cap_mem[((CVA6Cfg.XLEN * 2) - 1):CVA6Cfg.XLEN] = operand_b[XLEN-1:0];
                clu_result = cap_mem_to_cap_reg(cap_mem);
                clu_result.tag = 1'b0;
            end
            default: ; // default case to suppress unique warning
        endcase

        // Update destination register

    end

    // ----------------
    // Decode Cap Operands Fields
    // ----------------
    always_comb begin
        operand_a = fu_data_i.operand_a;
        operand_b = fu_data_i.operand_b;
        // Decode capability operand a fields
        op_a_meta_info = get_cap_reg_meta_data(operand_a);
        operand_a_address = operand_a.addr;
        operand_a_base   = get_cap_reg_base(operand_a, op_a_meta_info);
        operand_a_top    = get_cap_reg_top(operand_a, op_a_meta_info);
        operand_a_length = get_cap_reg_length(operand_a, op_a_meta_info);
        operand_a_is_sealed = (operand_a.otype != UNSEALED_CAP);
        operand_a_hperms_malformed = (operand_a.hperms != legalize_arch_perms(operand_a.hperms));
        operand_a_bounds_malformed = !are_cap_reg_bounds_valid(operand_a, op_a_meta_info);
        // Decode capability operand b fields
        operand_b_address = operand_b.addr;
        op_b_meta_info = get_cap_reg_meta_data(operand_b);
        operand_b_base   = get_cap_reg_base(operand_b, op_b_meta_info);
        operand_b_top    = get_cap_reg_top(operand_b, op_b_meta_info);
        operand_b_bounds_malformed = !are_cap_reg_bounds_valid(operand_b, op_b_meta_info);
        //operand_b_length = get_cap_reg_length(operand_b, op_b_meta_info};
        //operand_b_offset = get_cap_reg_offset(operand_b, op_b_meta_info);
        operand_b_is_sealed = (operand_b.otype != UNSEALED_CAP);
        operand_b_hperms_malformed = (operand_b.hperms != legalize_arch_perms(operand_b.hperms));
        // Decode pc metadata fields
        op_pc_meta_info = get_cap_reg_meta_data(pcc);
    end

    // ----------------
    // Common Operations
    // 1. Set address operation
    // 2. Set offset operation
    // ----------------
    always_comb begin
        res_set_addr = set_cap_reg_address(op_set_addr,
                                           address,
                                           op_meta_set_addr
                                        );

        res_set_offset = cap_reg_inc_offset(op_set_offset,
                                            address,
                                            offset,
                                            op_meta_set_offset,
                                            set_offset
                                        );
        res_set_bounds = set_cap_reg_bounds(op_set_bounds, operand_a_address, set_bounds_len);
    end

    // ----------------
    // Operands Exception Control Checks
    // ----------------
    always_comb begin
        operand_a_violations = {CAP_CHECK_NUM{1'b0}};
        operand_b_violations = {CAP_CHECK_NUM{1'b0}};
        // Operand a capability checks
        if (!is_cap_reg_valid(fu_data_i.operand_a)) begin
            operand_a_violations[TAG_CHECK_IDX] = 1'b1;
        end

        if (!is_cap_reg_valid(fu_data_i.operand_b)) begin
            operand_b_violations[TAG_CHECK_IDX] = 1'b1;
        end

        if (operand_a_is_sealed) begin
            operand_a_violations[SEAL_CHECK_IDX] = 1'b1;
        end

        if (operand_b_is_sealed) begin
            operand_b_violations[SEAL_CHECK_IDX] = 1'b1;
        end

        if (operand_a_address < operand_a_base) begin
            operand_a_violations[BOUNDS_CHECK_IDX] = 1'b1;
        end

        if ((operand_a_address + set_bounds_len) > operand_a_top) begin
            operand_a_violations[BOUNDS_CHECK_IDX] = 1'b1;
        end
    end

    // ------------------------
    // CHERI Output Logic
    // ------------------------
    always_comb begin: cheri_output_logic
        clu_result_o = clu_result;
        // Clear result capability tag if there was any violations
        if ((operand_a_violations & check_operand_a_violations) != 0 ||
            (operand_b_violations & check_operand_b_violations) != 0) begin
            clu_result_o.tag = 1'b0;
        end
    end
endmodule
