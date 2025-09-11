# Copyright 2018 ETH Zurich and University of Bologna.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>

# hard-coded to Genesys 2 for the moment

if {$::env(BOARD) eq "genesys2"} {
    add_files -fileset constrs_1 -norecurse constraints/genesys-2.xdc
} elseif {$::env(BOARD) eq "kc705"} {
      add_files -fileset constrs_1 -norecurse constraints/kc705.xdc
} elseif {$::env(BOARD) eq "vc707"} {
      add_files -fileset constrs_1 -norecurse constraints/vc707.xdc
} elseif {$::env(BOARD) eq "nexys_video"} {
      add_files -fileset constrs_1 -norecurse constraints/nexys_video.xdc
} else {
      exit 1
}

read_ip { \
      "xilinx/xlnx_mig_7_ddr3/xlnx_mig_7_ddr3.srcs/sources_1/ip/xlnx_mig_7_ddr3/xlnx_mig_7_ddr3.xci" \
      "xilinx/xlnx_axi_clock_converter/xlnx_axi_clock_converter.srcs/sources_1/ip/xlnx_axi_clock_converter/xlnx_axi_clock_converter.xci" \
      "xilinx/xlnx_axi_dwidth_converter/xlnx_axi_dwidth_converter.srcs/sources_1/ip/xlnx_axi_dwidth_converter/xlnx_axi_dwidth_converter.xci" \
      "xilinx/xlnx_axi_dwidth_converter_dm_slave/xlnx_axi_dwidth_converter_dm_slave.srcs/sources_1/ip/xlnx_axi_dwidth_converter_dm_slave/xlnx_axi_dwidth_converter_dm_slave.xci" \
      "xilinx/xlnx_axi_dwidth_converter_dm_master/xlnx_axi_dwidth_converter_dm_master.srcs/sources_1/ip/xlnx_axi_dwidth_converter_dm_master/xlnx_axi_dwidth_converter_dm_master.xci" \
      "xilinx/xlnx_axi_gpio/xlnx_axi_gpio.srcs/sources_1/ip/xlnx_axi_gpio/xlnx_axi_gpio.xci" \
      "xilinx/xlnx_axi_quad_spi/xlnx_axi_quad_spi.srcs/sources_1/ip/xlnx_axi_quad_spi/xlnx_axi_quad_spi.xci" \
      "xilinx/xlnx_clk_gen/xlnx_clk_gen.srcs/sources_1/ip/xlnx_clk_gen/xlnx_clk_gen.xci" \
}
# read_ip xilinx/xlnx_protocol_checker/ip/xlnx_protocol_checker.xci

#set_property include_dirs { \
#	"src/axi_sd_bridge/include" \
#	"../../vendor/pulp-platform/common_cells/include" \
#	"../../vendor/pulp-platform/axi/include" \
#      "../../vendor/zero-day/axi_tagcontroller/src/axi_llc/include/" \
#	"../../core/cache_subsystem/hpdcache/rtl/include" \
#	"../register_interface/include" \
#	"../../core/include" \
#} [current_fileset]

set_property include_dirs { \
  "src/axi_sd_bridge/include" \
  "../../core/include" \
} [current_fileset]

# This script was generated automatically by bender.

set VENDOR_ROOT "../../vendor"
set TECH_CELLS_GENERIC_ROOT "$VENDOR_ROOT/pulp-platform/tech_cells_generic"
set COMMON_CELLS_ROOT "$VENDOR_ROOT/pulp-platform/common_cells"
set AXI_ROOT "$VENDOR_ROOT/pulp-platform/axi"
set APB_ROOT "$VENDOR_ROOT/pulp-platform/apb"
set REGISTER_INTERFACE_ROOT "$VENDOR_ROOT/pulp-platform/register_interface"
set HPDCACHE_ROOT "$VENDOR_ROOT/capltd/cv-hpdcache"
set AXI_CHERI_TAGCONTROLLER_ROOT "$VENDOR_ROOT/capltd/axi_cheri_tagcontroller"

add_files -norecurse -fileset [current_fileset] [list \
    $TECH_CELLS_GENERIC_ROOT/src/fpga/pad_functional_xilinx.sv \
    $TECH_CELLS_GENERIC_ROOT/src/fpga/tc_clk_xilinx.sv \
    $TECH_CELLS_GENERIC_ROOT/src/fpga/tc_sram_xilinx.sv \
    $TECH_CELLS_GENERIC_ROOT/src/rtl/tc_sram_impl.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $TECH_CELLS_GENERIC_ROOT/src/deprecated/pulp_clock_gating_async.sv \
    $TECH_CELLS_GENERIC_ROOT/src/deprecated/cluster_clk_cells.sv \
    $TECH_CELLS_GENERIC_ROOT/src/deprecated/pulp_clk_cells.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $COMMON_CELLS_ROOT/src/binary_to_gray.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $COMMON_CELLS_ROOT/src/cb_filter_pkg.sv \
    $COMMON_CELLS_ROOT/src/cc_onehot.sv \
    $COMMON_CELLS_ROOT/src/cdc_reset_ctrlr_pkg.sv \
    $COMMON_CELLS_ROOT/src/cf_math_pkg.sv \
    $COMMON_CELLS_ROOT/src/clk_int_div.sv \
    $COMMON_CELLS_ROOT/src/credit_counter.sv \
    $COMMON_CELLS_ROOT/src/delta_counter.sv \
    $COMMON_CELLS_ROOT/src/ecc_pkg.sv \
    $COMMON_CELLS_ROOT/src/edge_propagator_tx.sv \
    $COMMON_CELLS_ROOT/src/exp_backoff.sv \
    $COMMON_CELLS_ROOT/src/fifo_v3.sv \
    $COMMON_CELLS_ROOT/src/gray_to_binary.sv \
    $COMMON_CELLS_ROOT/src/isochronous_4phase_handshake.sv \
    $COMMON_CELLS_ROOT/src/isochronous_spill_register.sv \
    $COMMON_CELLS_ROOT/src/lfsr.sv \
    $COMMON_CELLS_ROOT/src/lfsr_16bit.sv \
    $COMMON_CELLS_ROOT/src/lfsr_8bit.sv \
    $COMMON_CELLS_ROOT/src/lossy_valid_to_stream.sv \
    $COMMON_CELLS_ROOT/src/mv_filter.sv \
    $COMMON_CELLS_ROOT/src/onehot_to_bin.sv \
    $COMMON_CELLS_ROOT/src/plru_tree.sv \
    $COMMON_CELLS_ROOT/src/passthrough_stream_fifo.sv \
    $COMMON_CELLS_ROOT/src/popcount.sv \
    $COMMON_CELLS_ROOT/src/rr_arb_tree.sv \
    $COMMON_CELLS_ROOT/src/rstgen_bypass.sv \
    $COMMON_CELLS_ROOT/src/serial_deglitch.sv \
    $COMMON_CELLS_ROOT/src/shift_reg.sv \
    $COMMON_CELLS_ROOT/src/shift_reg_gated.sv \
    $COMMON_CELLS_ROOT/src/spill_register_flushable.sv \
    $COMMON_CELLS_ROOT/src/stream_demux.sv \
    $COMMON_CELLS_ROOT/src/stream_filter.sv \
    $COMMON_CELLS_ROOT/src/stream_fork.sv \
    $COMMON_CELLS_ROOT/src/stream_intf.sv \
    $COMMON_CELLS_ROOT/src/stream_join_dynamic.sv \
    $COMMON_CELLS_ROOT/src/stream_mux.sv \
    $COMMON_CELLS_ROOT/src/stream_throttle.sv \
    $COMMON_CELLS_ROOT/src/sub_per_hash.sv \
    $COMMON_CELLS_ROOT/src/sync.sv \
    $COMMON_CELLS_ROOT/src/sync_wedge.sv \
    $COMMON_CELLS_ROOT/src/unread.sv \
    $COMMON_CELLS_ROOT/src/read.sv \
    $COMMON_CELLS_ROOT/src/addr_decode_dync.sv \
    $COMMON_CELLS_ROOT/src/cdc_2phase.sv \
    $COMMON_CELLS_ROOT/src/cdc_4phase.sv \
    $COMMON_CELLS_ROOT/src/clk_int_div_static.sv \
    $COMMON_CELLS_ROOT/src/addr_decode.sv \
    $COMMON_CELLS_ROOT/src/addr_decode_napot.sv \
    $COMMON_CELLS_ROOT/src/multiaddr_decode.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $COMMON_CELLS_ROOT/src/cb_filter.sv \
    $COMMON_CELLS_ROOT/src/cdc_fifo_2phase.sv \
    $COMMON_CELLS_ROOT/src/clk_mux_glitch_free.sv \
    $COMMON_CELLS_ROOT/src/counter.sv \
    $COMMON_CELLS_ROOT/src/ecc_decode.sv \
    $COMMON_CELLS_ROOT/src/ecc_encode.sv \
    $COMMON_CELLS_ROOT/src/edge_detect.sv \
    $COMMON_CELLS_ROOT/src/lzc.sv \
    $COMMON_CELLS_ROOT/src/max_counter.sv \
    $COMMON_CELLS_ROOT/src/rstgen.sv \
    $COMMON_CELLS_ROOT/src/spill_register.sv \
    $COMMON_CELLS_ROOT/src/stream_delay.sv \
    $COMMON_CELLS_ROOT/src/stream_fifo.sv \
    $COMMON_CELLS_ROOT/src/stream_fork_dynamic.sv \
    $COMMON_CELLS_ROOT/src/stream_join.sv \
    $COMMON_CELLS_ROOT/src/cdc_reset_ctrlr.sv \
    $COMMON_CELLS_ROOT/src/cdc_fifo_gray.sv \
    $COMMON_CELLS_ROOT/src/fall_through_register.sv \
    $COMMON_CELLS_ROOT/src/id_queue.sv \
    $COMMON_CELLS_ROOT/src/stream_to_mem.sv \
    $COMMON_CELLS_ROOT/src/stream_arbiter_flushable.sv \
    $COMMON_CELLS_ROOT/src/stream_fifo_optimal_wrap.sv \
    $COMMON_CELLS_ROOT/src/stream_register.sv \
    $COMMON_CELLS_ROOT/src/stream_xbar.sv \
    $COMMON_CELLS_ROOT/src/cdc_fifo_gray_clearable.sv \
    $COMMON_CELLS_ROOT/src/cdc_2phase_clearable.sv \
    $COMMON_CELLS_ROOT/src/mem_to_banks_detailed.sv \
    $COMMON_CELLS_ROOT/src/stream_arbiter.sv \
    $COMMON_CELLS_ROOT/src/stream_omega_net.sv \
    $COMMON_CELLS_ROOT/src/mem_to_banks.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $COMMON_CELLS_ROOT/src/deprecated/clock_divider_counter.sv \
    $COMMON_CELLS_ROOT/src/deprecated/clk_div.sv \
    $COMMON_CELLS_ROOT/src/deprecated/find_first_one.sv \
    $COMMON_CELLS_ROOT/src/deprecated/generic_LFSR_8bit.sv \
    $COMMON_CELLS_ROOT/src/deprecated/generic_fifo.sv \
    $COMMON_CELLS_ROOT/src/deprecated/prioarbiter.sv \
    $COMMON_CELLS_ROOT/src/deprecated/pulp_sync.sv \
    $COMMON_CELLS_ROOT/src/deprecated/pulp_sync_wedge.sv \
    $COMMON_CELLS_ROOT/src/deprecated/rrarbiter.sv \
    $COMMON_CELLS_ROOT/src/deprecated/clock_divider.sv \
    $COMMON_CELLS_ROOT/src/deprecated/fifo_v2.sv \
    $COMMON_CELLS_ROOT/src/deprecated/fifo_v1.sv \
    $COMMON_CELLS_ROOT/src/edge_propagator_ack.sv \
    $COMMON_CELLS_ROOT/src/edge_propagator.sv \
    $COMMON_CELLS_ROOT/src/edge_propagator_rx.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $APB_ROOT/src/apb_pkg.sv \
    $APB_ROOT/src/apb_intf.sv \
    $APB_ROOT/src/apb_err_slv.sv \
    $APB_ROOT/src/apb_regs.sv \
    $APB_ROOT/src/apb_cdc.sv \
    $APB_ROOT/src/apb_demux.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $AXI_ROOT/src/axi_pkg.sv \
    $AXI_ROOT/src/axi_intf.sv \
    $AXI_ROOT/src/axi_atop_filter.sv \
    $AXI_ROOT/src/axi_burst_splitter_gran.sv \
    $AXI_ROOT/src/axi_burst_unwrap.sv \
    $AXI_ROOT/src/axi_bus_compare.sv \
    $AXI_ROOT/src/axi_cdc_dst.sv \
    $AXI_ROOT/src/axi_cdc_src.sv \
    $AXI_ROOT/src/axi_cut.sv \
    $AXI_ROOT/src/axi_delayer.sv \
    $AXI_ROOT/src/axi_demux_simple.sv \
    $AXI_ROOT/src/axi_dw_downsizer.sv \
    $AXI_ROOT/src/axi_dw_upsizer.sv \
    $AXI_ROOT/src/axi_fifo.sv \
    $AXI_ROOT/src/axi_fifo_delay_dyn.sv \
    $AXI_ROOT/src/axi_id_remap.sv \
    $AXI_ROOT/src/axi_id_prepend.sv \
    $AXI_ROOT/src/axi_isolate.sv \
    $AXI_ROOT/src/axi_join.sv \
    $AXI_ROOT/src/axi_lite_demux.sv \
    $AXI_ROOT/src/axi_lite_dw_converter.sv \
    $AXI_ROOT/src/axi_lite_from_mem.sv \
    $AXI_ROOT/src/axi_lite_join.sv \
    $AXI_ROOT/src/axi_lite_lfsr.sv \
    $AXI_ROOT/src/axi_lite_mailbox.sv \
    $AXI_ROOT/src/axi_lite_mux.sv \
    $AXI_ROOT/src/axi_lite_regs.sv \
    $AXI_ROOT/src/axi_lite_to_apb.sv \
    $AXI_ROOT/src/axi_lite_to_axi.sv \
    $AXI_ROOT/src/axi_modify_address.sv \
    $AXI_ROOT/src/axi_mux.sv \
    $AXI_ROOT/src/axi_rw_join.sv \
    $AXI_ROOT/src/axi_rw_split.sv \
    $AXI_ROOT/src/axi_serializer.sv \
    $AXI_ROOT/src/axi_slave_compare.sv \
    $AXI_ROOT/src/axi_throttle.sv \
    $AXI_ROOT/src/axi_to_detailed_mem.sv \
    $AXI_ROOT/src/axi_burst_splitter.sv \
    $AXI_ROOT/src/axi_cdc.sv \
    $AXI_ROOT/src/axi_demux.sv \
    $AXI_ROOT/src/axi_err_slv.sv \
    $AXI_ROOT/src/axi_dw_converter.sv \
    $AXI_ROOT/src/axi_from_mem.sv \
    $AXI_ROOT/src/axi_id_serialize.sv \
    $AXI_ROOT/src/axi_lfsr.sv \
    $AXI_ROOT/src/axi_multicut.sv \
    $AXI_ROOT/src/axi_to_axi_lite.sv \
    $AXI_ROOT/src/axi_to_mem.sv \
    $AXI_ROOT/src/axi_zero_mem.sv \
    $AXI_ROOT/src/axi_interleaved_xbar.sv \
    $AXI_ROOT/src/axi_iw_converter.sv \
    $AXI_ROOT/src/axi_lite_xbar.sv \
    $AXI_ROOT/src/axi_xbar_unmuxed.sv \
    $AXI_ROOT/src/axi_to_mem_banked.sv \
    $AXI_ROOT/src/axi_to_mem_interleaved.sv \
    $AXI_ROOT/src/axi_to_mem_split.sv \
    $AXI_ROOT/src/axi_xbar.sv \
    $AXI_ROOT/src/axi_xp.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $REGISTER_INTERFACE_ROOT/src/reg_intf.sv \
    $REGISTER_INTERFACE_ROOT/vendor/lowrisc_opentitan/src/prim_subreg_arb.sv \
    $REGISTER_INTERFACE_ROOT/vendor/lowrisc_opentitan/src/prim_subreg_ext.sv \
    $REGISTER_INTERFACE_ROOT/src/apb_to_reg.sv \
    $REGISTER_INTERFACE_ROOT/src/axi_lite_to_reg.sv \
    $REGISTER_INTERFACE_ROOT/src/axi_to_reg_v2.sv \
    $REGISTER_INTERFACE_ROOT/src/periph_to_reg.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_cdc.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_cut.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_demux.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_err_slv.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_filter_empty_writes.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_mux.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_to_apb.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_to_mem.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_to_tlul.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_to_axi.sv \
    $REGISTER_INTERFACE_ROOT/src/reg_uniform.sv \
    $REGISTER_INTERFACE_ROOT/vendor/lowrisc_opentitan/src/prim_subreg_shadow.sv \
    $REGISTER_INTERFACE_ROOT/vendor/lowrisc_opentitan/src/prim_subreg.sv \
    $REGISTER_INTERFACE_ROOT/src/deprecated/axi_to_reg.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_pkg.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_burst_cutter.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_data_way.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_merge_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_read_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_reg_pkg.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_reg_top.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_write_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/eviction_refill/axi_llc_ax_master.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/eviction_refill/axi_llc_r_master.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/eviction_refill/axi_llc_w_master.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/hit_miss_detect/axi_llc_evict_box.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/hit_miss_detect/axi_llc_lock_box_bloom.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/hit_miss_detect/axi_llc_miss_counters.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/hit_miss_detect/axi_llc_tag_pattern_gen.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_chan_splitter.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_evict_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_refill_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_ways.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/hit_miss_detect/axi_llc_tag_store.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_config.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_hit_miss.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_top.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/src/axi_llc_reg_wrap.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $HPDCACHE_ROOT/rtl/src/hpdcache_pkg.sv \
    $HPDCACHE_ROOT/rtl/src/utils/hpdcache_mem_req_read_arbiter.sv \
    $HPDCACHE_ROOT/rtl/src/utils/hpdcache_mem_req_write_arbiter.sv \
    $HPDCACHE_ROOT/rtl/src/utils/hpdcache_mem_to_axi_read.sv \
    $HPDCACHE_ROOT/rtl/src/utils/hpdcache_mem_to_axi_write.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_demux.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_lfsr.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_sync_buffer.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_fifo_reg.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_fifo_reg_initialized.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_fxarb.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_rrarb.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_mux.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_decoder.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_1hot_to_binary.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_prio_1hot_encoder.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_prio_bin_encoder.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_sram.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_sram_wbyteenable.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_sram_wmask.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_regbank_wbyteenable_1rw.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_regbank_wmask_1rw.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_data_downsize.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_data_upsize.sv \
    $HPDCACHE_ROOT/rtl/src/common/hpdcache_data_resize.sv \
    $HPDCACHE_ROOT/rtl/src/common/macros/behav/hpdcache_sram_1rw.sv \
    $HPDCACHE_ROOT/rtl/src/common/macros/behav/hpdcache_sram_wmask_1rw.sv \
    $HPDCACHE_ROOT/rtl/src/common/macros/behav/hpdcache_sram_wbyteenable_1rw.sv \
    $HPDCACHE_ROOT/rtl/src/hwpf_stride/hwpf_stride_pkg.sv \
    $HPDCACHE_ROOT/rtl/src/hwpf_stride/hwpf_stride.sv \
    $HPDCACHE_ROOT/rtl/src/hwpf_stride/hwpf_stride_arb.sv \
    $HPDCACHE_ROOT/rtl/src/hwpf_stride/hwpf_stride_wrapper.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_amo.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_cmo.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_core_arbiter.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_ctrl.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_ctrl_pe.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_memctrl.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_cbuf.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_flush.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_miss_handler.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_mshr.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_rtab.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_uncached.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_victim_plru.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_victim_random.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_victim_sel.sv \
    $HPDCACHE_ROOT/rtl/src/hpdcache_wbuf.sv \
]
add_files -norecurse -fileset [current_fileset] [list \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_pkg.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_data_way.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_ways.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/hpdcache_wrapper.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagc_read_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagc_write_unit.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_ax.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_config.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_r.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_w.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_top.sv \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_tagctrl_reg_wrap.sv \
]

set_property include_dirs [list \
  "src/axi_sd_bridge/include" \
  "../../core/include" \
    $APB_ROOT/include \
    $AXI_ROOT/include \
    $AXI_CHERI_TAGCONTROLLER_ROOT/src/axi_llc/include \
    $COMMON_CELLS_ROOT/include \
    $HPDCACHE_ROOT/rtl/include \
    $REGISTER_INTERFACE_ROOT/include \
] [current_fileset]

set_property verilog_define [list \
    TARGET_FPGA \
    TARGET_SYNTHESIS \
    TARGET_VIVADO \
    TARGET_XILINX \
] [current_fileset]

source scripts/add_sources.tcl

set_property top ${project}_xilinx [current_fileset]

if {$::env(BOARD) eq "genesys2"} {
    read_verilog -sv {src/genesysii.svh ../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
    set file "src/genesysii.svh"
    set registers "../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} elseif {$::env(BOARD) eq "kc705"} {
      read_verilog -sv {src/kc705.svh ../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
      set file "src/kc705.svh"
      set registers "../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} elseif {$::env(BOARD) eq "vc707"} {
      read_verilog -sv {src/vc707.svh ../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
      set file "src/vc707.svh"
      set registers "../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} elseif {$::env(BOARD) eq "nexys_video"} {
      read_verilog -sv {src/nexys_video.svh ../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh}
      set file "src/nexys_video.svh"
      set registers "../../vendor/pulp-platform/common_cells/include/common_cells/registers.svh"
} else {
    exit 1
}

set file_obj [get_files -of_objects [get_filesets sources_1] [list "*$file" "$registers"]]
set_property -dict { file_type {Verilog Header} is_global_include 1} -objects $file_obj

update_compile_order -fileset sources_1

add_files -fileset constrs_1 -norecurse constraints/$project.xdc

synth_design -rtl -name rtl_1

set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

launch_runs synth_1
wait_on_run synth_1
open_run synth_1

exec mkdir -p reports/
exec rm -rf reports/*

check_timing -verbose                                                   -file reports/$project.check_timing.rpt
report_timing -max_paths 100 -nworst 100 -delay_type max -sort_by slack -file reports/$project.timing_WORST_100.rpt
report_timing -nworst 1 -delay_type max -sort_by group                  -file reports/$project.timing.rpt
report_utilization -hierarchical                                        -file reports/$project.utilization.rpt
report_cdc                                                              -file reports/$project.cdc.rpt
report_clock_interaction                                                -file reports/$project.clock_interaction.rpt

# set for RuntimeOptimized implementation
#set_property "steps.opt_design.args.directive" "$opt_strat" [get_runs impl_1]
#set_property "steps.place_design.args.directive" "$place_strat" [get_runs impl_1]
#set_property "steps.route_design.args.directive" "$route_strat" [get_runs impl_1]

launch_runs impl_1
wait_on_run impl_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
open_run impl_1

# output Verilog netlist + SDC for timing simulation
write_verilog -force -mode funcsim work-fpga/${project}_funcsim.v
write_verilog -force -mode timesim work-fpga/${project}_timesim.v
write_sdf     -force work-fpga/${project}_timesim.sdf

# reports
exec mkdir -p reports/
exec rm -rf reports/*
check_timing                                                              -file reports/${project}.check_timing.rpt
report_timing -max_paths 100 -nworst 100 -delay_type max -sort_by slack   -file reports/${project}.timing_WORST_100.rpt
report_timing -nworst 1 -delay_type max -sort_by group                    -file reports/${project}.timing.rpt
report_utilization -hierarchical                                          -file reports/${project}.utilization.rpt
