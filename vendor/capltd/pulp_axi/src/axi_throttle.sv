// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Thomas Benz <tbenz@iis.ee.ethz.ch>

/// Throttles an AXI4+ATOP bus. The maximum number of outstanding transfers have to
/// be set as a compile-time parameter, whereas the number of outstanding transfers can be set
/// during runtime. This module assumes either in-order processing of the requests or
/// indistinguishability of the request/responses (all ARs and AWs have the same ID respectively).
///
/// Optionally (`MaxNumRBeatsPending > 0`), the module additionally limits the number of
/// outstanding read data beats, i.e., the sum of `len + 1` over all in-flight read bursts. An AR
/// is only forwarded if its R beats fit into the remaining read beat credit (`r_beat_credit_i`).
/// The credit of each beat is returned with its R handshake. To guarantee progress, a single
/// burst with more beats than `r_beat_credit_i` is forwarded once no R beats are outstanding.
/// Read beat limiting does not support ATOPs with read response (`AtomicLoad`, `AtomicSwap`,
/// `AtomicCompare`), as their R beats are not accounted for.
module axi_throttle #(
    /// The maximum amount of allowable outstanding write requests
    parameter int unsigned MaxNumAwPending = 1,
    /// The maximum amount of allowable outstanding read requests
    parameter int unsigned MaxNumArPending = 1,
    /// AXI4+ATOP request type
    parameter type axi_req_t = logic,
    /// AXI4+ATOP response type
    parameter type axi_rsp_t = logic,
    /// The maximum amount of allowable outstanding read data beats (R beats), 0 disables
    /// read beat limiting
    parameter int unsigned MaxNumRBeatsPending = 0,
    /// The width of the write credit counter (*DO NOT OVERWRITE*)
    parameter int unsigned WCntWidth = cf_math_pkg::idx_width(MaxNumAwPending),
    /// The width of the read credit counter (*DO NOT OVERWRITE*)
    parameter int unsigned RCntWidth = cf_math_pkg::idx_width(MaxNumArPending),
    /// The type of the write credit counter (*DO NOT OVERWRITE*)
    parameter type w_credit_t = logic [WCntWidth-1:0],
    /// The type of the read credit counter (*DO NOT OVERWRITE*)
    parameter type r_credit_t = logic [RCntWidth-1:0],
    /// The width of the read beat credit (*DO NOT OVERWRITE*)
    parameter int unsigned RBeatCntWidth = cf_math_pkg::idx_width(MaxNumRBeatsPending + 1),
    /// The type of the read beat credit (*DO NOT OVERWRITE*)
    parameter type r_beat_credit_t = logic [RBeatCntWidth-1:0]
) (
    /// Clock
    input  logic clk_i,
    /// Asynchronous reset, active low
    input  logic rst_ni,

    /// AXI4+ATOP request in
    input  axi_req_t req_i,
    /// AXI4+ATOP response out
    output axi_rsp_t rsp_o,
    /// AXI4+ATOP request out
    output axi_req_t req_o,
    /// AXI4+ATOP response in
    input  axi_rsp_t rsp_i,

    /// Amount of write credit (number of outstanding write transfers)
    input  w_credit_t w_credit_i,
    /// Amount of read credit (number of outstanding read transfers)
    input  r_credit_t r_credit_i,
    /// Amount of read beat credit (number of outstanding R beats), must be at least 1;
    /// unused if `MaxNumRBeatsPending == 0`
    input  r_beat_credit_t r_beat_credit_i
);

    // ax throttled valids
    logic throttled_aw_valid;
    logic throttled_ar_valid;

    // ax throttled readies
    logic throttled_aw_ready;
    logic throttled_ar_ready;

    // limit Aw requests -> wait for b
    stream_throttle #(
        .MaxNumPending ( MaxNumAwPending  )
    ) i_stream_throttle_aw (
        .clk_i,
        .rst_ni,
        .req_valid_i ( req_i.aw_valid     ),
        .req_valid_o ( throttled_aw_valid ),
        .req_ready_i ( rsp_i.aw_ready     ),
        .req_ready_o ( throttled_aw_ready ),
        .rsp_valid_i ( rsp_i.b_valid      ),
        .rsp_ready_i ( req_i.b_ready      ),
        .credit_i    ( w_credit_i         )
    );

    // limit R beats -> an AR only passes if its beats fit into the remaining read beat credit
    logic r_beats_available;

    if (MaxNumRBeatsPending > 0) begin : gen_r_beat_throttle
        // Wide enough for the beat credit and for the largest burst (256 beats).
        localparam int unsigned BeatCntWidth =
            cf_math_pkg::idx_width((MaxNumRBeatsPending > 256 ? MaxNumRBeatsPending : 256) + 1);
        typedef logic [BeatCntWidth-1:0] beat_cnt_t;

        beat_cnt_t r_beats_pending, ar_beats, r_beats_delta;
        logic      ar_hs, r_hs;

        assign ar_beats = beat_cnt_t'(req_i.ar.len) + beat_cnt_t'(1);
        assign ar_hs    = req_o.ar_valid & rsp_i.ar_ready;
        assign r_hs     = rsp_i.r_valid  & req_i.r_ready;

        // The AR fits into the remaining credit, or no R beats are pending (progress guarantee
        // for bursts larger than the credit).
        assign r_beats_available =
            ({1'b0, r_beats_pending} + {1'b0, ar_beats} <= {1'b0, beat_cnt_t'(r_beat_credit_i)}) ||
            (r_beats_pending == '0);

        // Count up by the beats of a forwarded AR, count down by one for each R beat.
        assign r_beats_delta = ar_hs ? (ar_beats - beat_cnt_t'(r_hs)) : beat_cnt_t'(1);

        delta_counter #(
            .WIDTH          ( BeatCntWidth )
        ) i_r_beat_counter (
            .clk_i,
            .rst_ni,
            .clear_i    ( 1'b0            ),
            .en_i       ( ar_hs | r_hs    ),
            .load_i     ( 1'b0            ),
            .down_i     ( ~ar_hs          ),
            .delta_i    ( r_beats_delta   ),
            .d_i        ( '0              ),
            .q_o        ( r_beats_pending ),
            .overflow_o ( /* not used */  )
        );

// pragma translate_off
`ifndef VERILATOR
`ifndef XILINX_SIMULATOR
        r_beat_credit_zero : assert property (@(posedge clk_i) disable iff (~rst_ni)
            (req_i.ar_valid |-> r_beat_credit_i != '0))
            else $error("The read beat credit must be at least 1.");
        r_beat_credit_max : assert property (@(posedge clk_i) disable iff (~rst_ni)
            (req_i.ar_valid |-> r_beat_credit_i <= MaxNumRBeatsPending))
            else $error("The read beat credit exceeds MaxNumRBeatsPending.");
        r_beat_underflow : assert property (@(posedge clk_i) disable iff (~rst_ni)
            (r_hs |-> r_beats_pending != '0))
            else $error("R beat without pending read beat (ATOPs with R response unsupported).");
        no_atop_r_resp : assert property (@(posedge clk_i) disable iff (~rst_ni)
            (req_i.aw_valid |-> !req_i.aw.atop[axi_pkg::ATOP_R_RESP]))
            else $error("ATOPs with R response are not supported with read beat limiting.");
`endif
`endif
// pragma translate_on
    end else begin : gen_no_r_beat_throttle
        assign r_beats_available = 1'b1;
    end

    // limit Ar requests -> wait for r.last
    stream_throttle #(
        .MaxNumPending ( MaxNumArPending  )
    ) i_stream_throttle_ar (
        .clk_i,
        .rst_ni,
        .req_valid_i ( req_i.ar_valid & r_beats_available  ),
        .req_valid_o ( throttled_ar_valid                  ),
        .req_ready_i ( rsp_i.ar_ready & r_beats_available  ),
        .req_ready_o ( throttled_ar_ready                  ),
        .rsp_valid_i ( rsp_i.r_valid & rsp_i.r.last        ),
        .rsp_ready_i ( req_i.r_ready                       ),
        .credit_i    ( r_credit_i                          )
    );

    // connect the throttled request bus (its a through connection - except for the ax valids)
    always_comb begin : gen_throttled_req_conn
        req_o          = req_i;
        req_o.aw_valid = throttled_aw_valid;
        req_o.ar_valid = throttled_ar_valid;
    end

    // connect the throttled response bus (its a through connection - except for the ax readies)
    always_comb begin : gen_throttled_rsp_conn
        rsp_o          = rsp_i;
        rsp_o.aw_ready = throttled_aw_ready;
        rsp_o.ar_ready = throttled_ar_ready;
    end

endmodule : axi_throttle
