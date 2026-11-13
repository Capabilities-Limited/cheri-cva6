// Copyright (c) 2026 Capabilities Limited.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Authors:
// - Jonathan Woodruff <jonathan.woodruff@capabilitieslimited.co.uk>

`include "common_cells/registers.svh"

/// Filter read-after-write, write-after-read, and write-after-write hazards on an AXI4+ATOP bus.
///
/// This module guarantees the following invariant at its master port: for any memory region, there
/// is either
/// - at most **one** write transaction in flight, and no read transaction, or
/// - any number of read transactions in flight, and no write transaction.
///
/// To enforce this, the module keeps a table of the address ranges of all write and all read
/// transactions that are in flight downstream:
/// - An AW is stalled while it overlaps an in-flight write *or* an in-flight read.
/// - An AR is stalled while it overlaps an in-flight write.
/// - A write is in flight from its AW handshake until its B handshake at the slave port.  A read is
///   in flight from its AR handshake until the handshake of its last R beat at the slave port.
/// - If an AW and an AR are valid in the same cycle and overlap each other, only one of them is
///   forwarded.  The priority alternates between the two to avoid starving either direction.
///
/// The W, B, and R channels are passed through unchanged; the module only stalls AW and AR.  It
/// does not reorder transactions and does not modify any payload.
///
/// ## Regions
///
/// The address range of a burst is computed conservatively from `addr`, `size`, `len`, and `burst`
/// (aligned to `size` for `FIXED` and `INCR` bursts, and to the wrap boundary for `WRAP` bursts).
/// Two transactions are considered to overlap if their address ranges touch at least one common
/// region of `RegionSize` bytes.  With `RegionSize = 1`, overlaps are detected at byte granularity.
/// A larger `RegionSize` (e.g., the cache line size) narrows the comparators at the cost of
/// detecting false hazards between transactions that share a region but not a byte.
///
/// As an AXI burst never crosses a 4 KiB boundary (AXI Spec A3.4.1), all bytes of a burst share
/// the same page number (address bits above bit 11).  The range of a burst is therefore stored as
/// the regions it touches within its page, plus a `PageHashWidth`-bit hash of its page number,
/// formed by XOR-folding the page number.  Two transactions overlap if their page hashes are equal
/// and their in-page ranges intersect.  If the page number is wider than the hash, different pages
/// can share a hash; this only causes false hazards (stalls), never a missed hazard.  If the page
/// number fits into the hash, it is compared exactly.
///
/// ## Atomic Operations
///
/// An ATOP is treated as a write.  An ATOP that has an R response (`AtomicLoad`, `AtomicSwap`,
/// `AtomicCompare`) is additionally tracked as a read of the same range, which retires with its
/// last R beat.  The region is thus released only after both its B and its R response.  This
/// relies on the AXI requirement that the ID of an ATOP is unique among all in-flight transactions
/// (AXI Spec E1.1.4).
///
/// ## Limitations
///
/// - At most `MaxWriteTxns` writes and `MaxReadTxns` reads can be in flight; further transactions
///   of a direction are stalled until one of that direction completes.
/// - The module does not reorder transactions.  A stalled AW (AR) thus blocks all later AWs (ARs),
///   even ones that do not overlap any in-flight transaction.
/// - A continuous stream of overlapping reads that keeps a region busy without interruption can
///   starve a write to that region (and vice versa).
/// - A transaction is retired one cycle after its response handshake, i.e., a transaction stalled
///   on it is forwarded one cycle after the response at the earliest.
/// - Bursts that illegally cross a 4 KiB boundary are not supported (an assertion flags them).
module axi_hazard_filter #(
  /// Maximum number of in-flight read transactions.
  parameter int unsigned MaxReadTxns  = 32'd0,
  /// Maximum number of in-flight write transactions.
  parameter int unsigned MaxWriteTxns = 32'd0,
  /// AXI4+ATOP ID width.
  parameter int unsigned AxiIdWidth   = 32'd0,
  /// AXI4+ATOP address width.
  parameter int unsigned AxiAddrWidth = 32'd0,
  /// Granularity of hazard detection in bytes.  Must be a power of two and at most 4096.
  parameter int unsigned RegionSize    = 32'd1,
  /// Width of the hash of the page number (address bits above bit 11) stored per transaction.
  parameter int unsigned PageHashWidth = 32'd16,
  /// AXI4+ATOP request struct definition.
  parameter type         axi_req_t    = logic,
  /// AXI4+ATOP response struct definition.
  parameter type         axi_resp_t   = logic
) (
  /// Clock
  input  logic      clk_i,
  /// Asynchronous reset, active low
  input  logic      rst_ni,
  /// Slave port request
  input  axi_req_t  slv_req_i,
  /// Slave port response
  output axi_resp_t slv_resp_o,
  /// Master port request
  output axi_req_t  mst_req_o,
  /// Master port response
  input  axi_resp_t mst_resp_i
);

  /// AXI bursts never cross a 4 KiB boundary, so the page number of all bytes of a burst is equal.
  localparam int unsigned PageOffsetWidth   = 32'd12;
  localparam int unsigned RegionOffsetWidth = $clog2(RegionSize);
  /// Index of a region within a page (at least one bit wide, to keep the types legal).
  localparam int unsigned RegionIdxWidth    = (PageOffsetWidth > RegionOffsetWidth) ?
                                              (PageOffsetWidth - RegionOffsetWidth) : 32'd1;
  localparam int unsigned WrSlotIdxWidth    = cf_math_pkg::idx_width(MaxWriteTxns);
  localparam int unsigned RdSlotIdxWidth    = cf_math_pkg::idx_width(MaxReadTxns);

  typedef logic [AxiIdWidth-1:0]     id_t;
  typedef logic [AxiAddrWidth-1:0]   addr_t;
  typedef logic [RegionIdxWidth-1:0] region_idx_t;
  typedef logic [PageHashWidth-1:0]  page_hash_t;
  typedef logic [WrSlotIdxWidth-1:0] wr_slot_idx_t;
  typedef logic [RdSlotIdxWidth-1:0] rd_slot_idx_t;

  /// First and last byte address accessed by a burst.
  typedef struct packed {
    addr_t first;
    addr_t last;
  } bounds_t;

  /// Range of regions accessed by a burst: the hash of its page number and the inclusive range of
  /// regions it touches within that page.
  typedef struct packed {
    page_hash_t  page;
    region_idx_t first;
    region_idx_t last;
  } range_t;

  /// Compute the (conservative) first and last byte address accessed by a burst.
  function automatic bounds_t burst_bounds(addr_t addr, axi_pkg::size_t size, axi_pkg::len_t len,
                                           axi_pkg::burst_t burst);
    addr_t   first_addr, last_addr, num_bytes;
    bounds_t bounds;
    num_bytes = (addr_t'(len) + addr_t'(1)) << size;
    unique case (burst)
      axi_pkg::BURST_FIXED: begin
        first_addr = addr_t'(axi_pkg::aligned_addr(axi_pkg::largest_addr_t'(addr), size));
        last_addr  = first_addr + addr_t'(axi_pkg::num_bytes(size)) - addr_t'(1);
      end
      axi_pkg::BURST_WRAP: begin
        // The total size of a legal wrapping burst is a power of two, so aligning to it yields the
        // wrap boundary.  This avoids `axi_pkg::wrap_boundary()`, whose assumption on `len` would
        // fire on the (don't care) payload of idle channels.
        first_addr = addr & ~(num_bytes - addr_t'(1));
        last_addr  = first_addr + num_bytes - addr_t'(1);
      end
      default: begin // `BURST_INCR` (and reserved burst type, conservatively)
        first_addr = addr_t'(axi_pkg::aligned_addr(axi_pkg::largest_addr_t'(addr), size));
        last_addr  = first_addr + num_bytes - addr_t'(1);
      end
    endcase
    bounds.first = first_addr;
    bounds.last  = last_addr;
    return bounds;
  endfunction

  /// XOR-fold the page number (the address bits above the page offset) into a hash.
  function automatic page_hash_t page_hash(axi_pkg::largest_addr_t addr);
    page_hash_t hash = '0;
    for (int unsigned i = PageOffsetWidth; i < AxiAddrWidth; i++) begin
      hash[(i - PageOffsetWidth) % PageHashWidth] ^= addr[i];
    end
    return hash;
  endfunction

  /// Index of the region within its page that contains a byte (given by its offset in the page).
  function automatic region_idx_t region_idx(logic [PageOffsetWidth-1:0] page_offset);
    return region_idx_t'(page_offset >> RegionOffsetWidth);
  endfunction

  /// Convert the bounds of a burst (which lie within one page) to its range of regions.
  function automatic range_t to_range(bounds_t bounds);
    range_t range;
    range.page  = page_hash(axi_pkg::largest_addr_t'(bounds.first));
    range.first = region_idx(bounds.first[PageOffsetWidth-1:0]);
    range.last  = region_idx(bounds.last[PageOffsetWidth-1:0]);
    return range;
  endfunction

  /// Determine whether two ranges (may) share at least one region.
  function automatic logic overlaps(range_t a, range_t b);
    return (a.page == b.page) && (a.first <= b.last) && (b.first <= a.last);
  endfunction

  // Address ranges of the incoming transactions.
  bounds_t aw_bounds, ar_bounds;
  range_t  aw_range,  ar_range;
  assign aw_bounds = burst_bounds(slv_req_i.aw.addr, slv_req_i.aw.size, slv_req_i.aw.len,
                                  slv_req_i.aw.burst);
  assign ar_bounds = burst_bounds(slv_req_i.ar.addr, slv_req_i.ar.size, slv_req_i.ar.len,
                                  slv_req_i.ar.burst);
  assign aw_range  = to_range(aw_bounds);
  assign ar_range  = to_range(ar_bounds);

  // An ATOP with R response also occupies a slot in the read table.
  logic aw_atop_r_resp;
  assign aw_atop_r_resp = slv_req_i.aw.atop[axi_pkg::ATOP_R_RESP];

  //////////////////////////////
  // In-flight transaction tables
  //////////////////////////////

  // Write table
  logic   [MaxWriteTxns-1:0] wr_valid_d, wr_valid_q;
  range_t [MaxWriteTxns-1:0] wr_range_q;
  logic   [MaxWriteTxns-1:0] wr_alloc;
  logic                      wr_full;
  wr_slot_idx_t              wr_free_idx, wr_retire_idx;
  // Read table
  logic   [MaxReadTxns-1:0]  rd_valid_d,  rd_valid_q;
  range_t [MaxReadTxns-1:0]  rd_range_d,  rd_range_q;
  logic   [MaxReadTxns-1:0]  rd_alloc;
  logic                      rd_full;
  rd_slot_idx_t              rd_free_idx, rd_retire_idx;

  // Find a free slot in each table.
  lzc #(
    .WIDTH ( MaxWriteTxns ),
    .MODE  ( 1'b0         ) // trailing zero count
  ) i_wr_free_lzc (
    .in_i    ( ~wr_valid_q ),
    .cnt_o   ( wr_free_idx ),
    .empty_o ( wr_full     )
  );

  lzc #(
    .WIDTH ( MaxReadTxns  ),
    .MODE  ( 1'b0         ) // trailing zero count
  ) i_rd_free_lzc (
    .in_i    ( ~rd_valid_q ),
    .cnt_o   ( rd_free_idx ),
    .empty_o ( rd_full     )
  );

  ///////////////////
  // Hazard detection
  ///////////////////

  // Compare against the registered tables only: this keeps the AW/AR valids independent of the
  // B/R handshakes at the cost of one cycle of latency on retirement.
  logic [MaxWriteTxns-1:0] aw_wr_hit, ar_wr_hit;
  logic [MaxReadTxns-1:0]  aw_rd_hit;

  for (genvar i = 0; i < MaxWriteTxns; i++) begin : gen_wr_cmp
    assign aw_wr_hit[i] = wr_valid_q[i] & overlaps(wr_range_q[i], aw_range);
    assign ar_wr_hit[i] = wr_valid_q[i] & overlaps(wr_range_q[i], ar_range);
  end
  for (genvar i = 0; i < MaxReadTxns; i++) begin : gen_rd_cmp
    assign aw_rd_hit[i] = rd_valid_q[i] & overlaps(rd_range_q[i], aw_range);
  end

  // A transaction is free of hazards w.r.t. in-flight transactions and has resources to be tracked.
  logic aw_ok, ar_ok;
  assign aw_ok = slv_req_i.aw_valid & ~(|aw_wr_hit) & ~(|aw_rd_hit) & ~wr_full &
                 ~(aw_atop_r_resp & rd_full);
  assign ar_ok = slv_req_i.ar_valid & ~(|ar_wr_hit) & ~rd_full;

  // AW and AR in the same cycle must not be forwarded together if they overlap.  An ATOP with R
  // response is never forwarded together with an AR, as both allocate in the read table.
  logic aw_ar_conflict;
  assign aw_ar_conflict = slv_req_i.aw_valid & slv_req_i.ar_valid &
                          (overlaps(aw_range, ar_range) | aw_atop_r_resp);

  ////////////////////////
  // Forwarding of AW and AR
  ////////////////////////

  // Once a valid is applied downstream it must stay asserted until the handshake (AXI A3.2.1).  A
  // `*_lock_q` flag remembers that an AW (AR) is pending downstream.  A pending AW (AR) is free of
  // hazards, as only transactions that do not conflict with it are forwarded while it is pending.
  logic aw_lock_d, aw_lock_q, ar_lock_d, ar_lock_q;
  // Priority for conflicting AW and AR in the same cycle: 1 = write first, 0 = read first.
  logic prio_wr_d, prio_wr_q;
  logic aw_fwd, ar_fwd;

  always_comb begin
    aw_fwd    = aw_lock_q | aw_ok;
    ar_fwd    = ar_lock_q | ar_ok;
    prio_wr_d = prio_wr_q;
    if (aw_fwd && ar_fwd && aw_ar_conflict) begin
      // At most one of them can be pending, as conflicting AW and AR are never forwarded together.
      if (aw_lock_q) begin
        ar_fwd = 1'b0;
      end else if (ar_lock_q) begin
        aw_fwd = 1'b0;
      end else begin
        if (prio_wr_q) begin
          ar_fwd = 1'b0;
        end else begin
          aw_fwd = 1'b0;
        end
        prio_wr_d = ~prio_wr_q;
      end
    end
  end

  logic aw_hs, ar_hs, b_hs, r_last_hs;
  assign aw_hs     = mst_req_o.aw_valid & mst_resp_i.aw_ready;
  assign ar_hs     = mst_req_o.ar_valid & mst_resp_i.ar_ready;
  assign b_hs      = slv_resp_o.b_valid & slv_req_i.b_ready;
  assign r_last_hs = slv_resp_o.r_valid & slv_req_i.r_ready & slv_resp_o.r.last;

  assign aw_lock_d = mst_req_o.aw_valid & ~mst_resp_i.aw_ready;
  assign ar_lock_d = mst_req_o.ar_valid & ~mst_resp_i.ar_ready;

  always_comb begin
    // Default: feed through all channels.
    mst_req_o  = slv_req_i;
    slv_resp_o = mst_resp_i;
    // Gate AW and AR handshakes.
    mst_req_o.aw_valid  = slv_req_i.aw_valid  & aw_fwd;
    slv_resp_o.aw_ready = mst_resp_i.aw_ready & aw_fwd;
    mst_req_o.ar_valid  = slv_req_i.ar_valid  & ar_fwd;
    slv_resp_o.ar_ready = mst_resp_i.ar_ready & ar_fwd;
  end

  ///////////////////////////////
  // Allocation and retirement
  ///////////////////////////////

  // The per-ID ordering of responses is tracked in ID queues that hold the table slot of each
  // in-flight transaction.  A response retires the oldest in-flight transaction of its ID.
  logic wr_idq_inp_gnt, wr_idq_oup_valid;
  logic rd_idq_inp_req, rd_idq_inp_gnt, rd_idq_oup_valid;
  id_t  rd_idq_inp_id;

  id_queue #(
    .ID_WIDTH ( AxiIdWidth    ),
    .CAPACITY ( MaxWriteTxns  ),
    .FULL_BW  ( 1'b1          ),
    .data_t   ( wr_slot_idx_t )
  ) i_wr_id_queue (
    .clk_i,
    .rst_ni,
    .inp_id_i         ( slv_req_i.aw.id   ),
    .inp_data_i       ( wr_free_idx       ),
    .inp_req_i        ( aw_hs             ),
    .inp_gnt_o        ( wr_idq_inp_gnt    ),
    .exists_data_i    ( '0                ),
    .exists_mask_i    ( '0                ),
    .exists_req_i     ( 1'b0              ),
    .exists_o         ( /* not used */    ),
    .exists_gnt_o     ( /* not used */    ),
    .oup_id_i         ( mst_resp_i.b.id   ),
    .oup_pop_i        ( b_hs              ),
    .oup_req_i        ( b_hs              ),
    .oup_data_o       ( wr_retire_idx     ),
    .oup_data_valid_o ( wr_idq_oup_valid  ),
    .oup_gnt_o        ( /* not used */    )
  );

  assign rd_idq_inp_req = ar_hs | (aw_hs & aw_atop_r_resp);
  assign rd_idq_inp_id  = ar_hs ? slv_req_i.ar.id : slv_req_i.aw.id;

  id_queue #(
    .ID_WIDTH ( AxiIdWidth    ),
    .CAPACITY ( MaxReadTxns   ),
    .FULL_BW  ( 1'b1          ),
    .data_t   ( rd_slot_idx_t )
  ) i_rd_id_queue (
    .clk_i,
    .rst_ni,
    .inp_id_i         ( rd_idq_inp_id     ),
    .inp_data_i       ( rd_free_idx       ),
    .inp_req_i        ( rd_idq_inp_req    ),
    .inp_gnt_o        ( rd_idq_inp_gnt    ),
    .exists_data_i    ( '0                ),
    .exists_mask_i    ( '0                ),
    .exists_req_i     ( 1'b0              ),
    .exists_o         ( /* not used */    ),
    .exists_gnt_o     ( /* not used */    ),
    .oup_id_i         ( mst_resp_i.r.id   ),
    .oup_pop_i        ( r_last_hs         ),
    .oup_req_i        ( r_last_hs         ),
    .oup_data_o       ( rd_retire_idx     ),
    .oup_data_valid_o ( rd_idq_oup_valid  ),
    .oup_gnt_o        ( /* not used */    )
  );

  always_comb begin
    wr_valid_d = wr_valid_q;
    wr_alloc   = '0;
    if (b_hs) begin
      wr_valid_d[wr_retire_idx] = 1'b0;
    end
    if (aw_hs) begin
      wr_alloc[wr_free_idx]   = 1'b1;
      wr_valid_d[wr_free_idx] = 1'b1;
    end
  end

  always_comb begin
    rd_valid_d = rd_valid_q;
    rd_range_d = rd_range_q;
    rd_alloc   = '0;
    if (r_last_hs) begin
      rd_valid_d[rd_retire_idx] = 1'b0;
    end
    if (rd_idq_inp_req) begin
      rd_alloc[rd_free_idx]   = 1'b1;
      rd_valid_d[rd_free_idx] = 1'b1;
      rd_range_d[rd_free_idx] = ar_hs ? ar_range : aw_range;
    end
  end

  for (genvar i = 0; i < MaxWriteTxns; i++) begin : gen_wr_range_reg
    `FFL(wr_range_q[i], aw_range, wr_alloc[i], '0, clk_i, rst_ni)
  end
  for (genvar i = 0; i < MaxReadTxns; i++) begin : gen_rd_range_reg
    `FFL(rd_range_q[i], rd_range_d[i], rd_alloc[i], '0, clk_i, rst_ni)
  end
  `FF(wr_valid_q, wr_valid_d, '0,   clk_i, rst_ni)
  `FF(rd_valid_q, rd_valid_d, '0,   clk_i, rst_ni)
  `FF(aw_lock_q,  aw_lock_d,  1'b0, clk_i, rst_ni)
  `FF(ar_lock_q,  ar_lock_d,  1'b0, clk_i, rst_ni)
  `FF(prio_wr_q,  prio_wr_d,  1'b0, clk_i, rst_ni)

// pragma translate_off
`ifndef VERILATOR
  initial begin: p_assertions
    assert (AxiIdWidth   >= 1) else $fatal(1, "AXI ID width must be at least 1!");
    assert (AxiAddrWidth >= 1) else $fatal(1, "AXI address width must be at least 1!");
    assert (MaxReadTxns  >= 1)
      else $fatal(1, "Maximum number of read transactions must be >= 1!");
    assert (MaxWriteTxns >= 1)
      else $fatal(1, "Maximum number of write transactions must be >= 1!");
    assert (RegionSize >= 1 && (RegionSize & (RegionSize - 1)) == 0)
      else $fatal(1, "RegionSize must be a power of two!");
    assert (RegionOffsetWidth <= PageOffsetWidth)
      else $fatal(1, "RegionSize must be at most 4 KiB!");
    assert (AxiAddrWidth >= PageOffsetWidth)
      else $fatal(1, "AXI address width must be at least 12 bit!");
    assert (PageHashWidth >= 1) else $fatal(1, "PageHashWidth must be at least 1!");
  end
`ifndef XILINX_SIMULATOR
  default disable iff (~rst_ni);
  aw_lost : assert property( @(posedge clk_i)
      (slv_req_i.aw_valid & slv_resp_o.aw_ready |-> mst_req_o.aw_valid & mst_resp_i.aw_ready))
    else $error("AW beat lost.");
  w_lost  : assert property( @(posedge clk_i)
      (slv_req_i.w_valid & slv_resp_o.w_ready |-> mst_req_o.w_valid & mst_resp_i.w_ready))
    else $error("W beat lost.");
  b_lost  : assert property( @(posedge clk_i)
      (mst_resp_i.b_valid & mst_req_o.b_ready |-> slv_resp_o.b_valid & slv_req_i.b_ready))
    else $error("B beat lost.");
  ar_lost : assert property( @(posedge clk_i)
      (slv_req_i.ar_valid & slv_resp_o.ar_ready |-> mst_req_o.ar_valid & mst_resp_i.ar_ready))
    else $error("AR beat lost.");
  r_lost  : assert property( @(posedge clk_i)
      (mst_resp_i.r_valid & mst_req_o.r_ready |-> slv_resp_o.r_valid & slv_req_i.r_ready))
    else $error("R beat lost.");
  aw_stable : assert property( @(posedge clk_i)
      (mst_req_o.aw_valid & ~mst_resp_i.aw_ready |=> mst_req_o.aw_valid))
    else $error("AW valid deasserted without handshake.");
  ar_stable : assert property( @(posedge clk_i)
      (mst_req_o.ar_valid & ~mst_resp_i.ar_ready |=> mst_req_o.ar_valid))
    else $error("AR valid deasserted without handshake.");
  wr_alloc_gnt : assert property( @(posedge clk_i) (aw_hs |-> wr_idq_inp_gnt))
    else $error("Write ID queue did not accept a new transaction.");
  rd_alloc_gnt : assert property( @(posedge clk_i) (rd_idq_inp_req |-> rd_idq_inp_gnt))
    else $error("Read ID queue did not accept a new transaction.");
  aw_4kib : assert property( @(posedge clk_i) (slv_req_i.aw_valid |->
      (aw_bounds.first >> PageOffsetWidth) == (aw_bounds.last >> PageOffsetWidth)))
    else $error("AW burst crosses a 4 KiB boundary.");
  ar_4kib : assert property( @(posedge clk_i) (slv_req_i.ar_valid |->
      (ar_bounds.first >> PageOffsetWidth) == (ar_bounds.last >> PageOffsetWidth)))
    else $error("AR burst crosses a 4 KiB boundary.");
  rd_alloc_excl : assert property( @(posedge clk_i) !(ar_hs & aw_hs & aw_atop_r_resp))
    else $error("AR and ATOP with R response allocated in the read table in the same cycle.");
  b_unexpected : assert property( @(posedge clk_i) (b_hs |-> wr_idq_oup_valid))
    else $error("B response with ID %0h without in-flight write.", mst_resp_i.b.id);
  r_unexpected : assert property( @(posedge clk_i) (r_last_hs |-> rd_idq_oup_valid))
    else $error("Last R response with ID %0h without in-flight read.", mst_resp_i.r.id);
`endif
`endif
// pragma translate_on
endmodule

`include "axi/typedef.svh"
`include "axi/assign.svh"
/// Filter read-after-write, write-after-read, and write-after-write hazards on an AXI4+ATOP bus,
/// interface version.
module axi_hazard_filter_intf #(
  /// AXI4+ATOP ID width.
  parameter int unsigned AXI_ID_WIDTH   = 32'd0,
  /// AXI4+ATOP address width.
  parameter int unsigned AXI_ADDR_WIDTH = 32'd0,
  /// AXI4+ATOP data width.
  parameter int unsigned AXI_DATA_WIDTH = 32'd0,
  /// AXI4+ATOP user width.
  parameter int unsigned AXI_USER_WIDTH = 32'd0,
  /// Maximum number of in-flight read transactions.
  parameter int unsigned MAX_READ_TXNS  = 32'd0,
  /// Maximum number of in-flight write transactions.
  parameter int unsigned MAX_WRITE_TXNS = 32'd0,
  /// Granularity of hazard detection in bytes.  Must be a power of two and at most 4096.
  parameter int unsigned REGION_SIZE     = 32'd1,
  /// Width of the hash of the page number (address bits above bit 11) stored per transaction.
  parameter int unsigned PAGE_HASH_WIDTH = 32'd16
) (
  /// Clock
  input  logic    clk_i,
  /// Asynchronous reset, active low
  input  logic    rst_ni,
  /// AXI4+ATOP Slave modport
  AXI_BUS.Slave   slv,
  /// AXI4+ATOP Master modport
  AXI_BUS.Master  mst
);

  typedef logic [AXI_ID_WIDTH    -1:0] id_t;
  typedef logic [AXI_ADDR_WIDTH  -1:0] addr_t;
  typedef logic [AXI_DATA_WIDTH  -1:0] data_t;
  typedef logic [AXI_DATA_WIDTH/8-1:0] strb_t;
  typedef logic [AXI_USER_WIDTH  -1:0] user_t;
  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)
  `AXI_TYPEDEF_REQ_T(axi_req_t, aw_chan_t, w_chan_t, ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_resp_t, b_chan_t, r_chan_t)
  axi_req_t  slv_req,  mst_req;
  axi_resp_t slv_resp, mst_resp;
  `AXI_ASSIGN_TO_REQ(slv_req, slv)
  `AXI_ASSIGN_FROM_RESP(slv, slv_resp)
  `AXI_ASSIGN_FROM_REQ(mst, mst_req)
  `AXI_ASSIGN_TO_RESP(mst_resp, mst)

  axi_hazard_filter #(
    .MaxReadTxns  ( MAX_READ_TXNS  ),
    .MaxWriteTxns ( MAX_WRITE_TXNS ),
    .AxiIdWidth   ( AXI_ID_WIDTH   ),
    .AxiAddrWidth ( AXI_ADDR_WIDTH ),
    .RegionSize    ( REGION_SIZE     ),
    .PageHashWidth ( PAGE_HASH_WIDTH ),
    .axi_req_t    ( axi_req_t      ),
    .axi_resp_t   ( axi_resp_t     )
  ) i_axi_hazard_filter (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( slv_req  ),
    .slv_resp_o ( slv_resp ),
    .mst_req_o  ( mst_req  ),
    .mst_resp_i ( mst_resp )
  );

// pragma translate_off
`ifndef VERILATOR
  initial begin: p_assertions
    assert (AXI_ADDR_WIDTH  >= 1) else $fatal(1, "AXI address width must be at least 1!");
    assert (AXI_DATA_WIDTH  >= 1) else $fatal(1, "AXI data width must be at least 1!");
    assert (AXI_ID_WIDTH    >= 1) else $fatal(1, "AXI ID width must be at least 1!");
    assert (AXI_USER_WIDTH  >= 1) else $fatal(1, "AXI user width must be at least 1!");
  end
`endif
// pragma translate_on
endmodule
