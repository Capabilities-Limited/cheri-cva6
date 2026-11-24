// Copyright 2026 Capabilities Limited
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.
//
// Description: Instruction cache built on a read-only HPDcache, with the interface of cva6_icache
//              (frontend requests, address translation and the I$ miss interface of the cache
//              subsystem), so that it can replace it.
//
//              The HPDcache is read-only (no write-through nor write-back), so that all its
//              cachelines are clean: with ECC (DcacheEccEnable), every error is either corrected
//              or recovered by refetching the cacheline from memory.
//
//              Requests are virtually indexed and physically tagged: the HPDcache request is sent
//              with the page offset of the fetch address, and its tag (from the address
//              translation) the next cycle. When the translation is not available that cycle (or
//              a speculative fetch targets a non-idempotent region), the request is aborted and
//              sent again once the translation is available. As in cva6_icache, the cache is
//              invalidated on a flush (fence.i) and when it is enabled, and fetches are
//              uncacheable when the cache is disabled or the address is not in a cacheable region.
//
//              The memory interface of the HPDcache is as wide as a cacheline, and each memory read
//              (a cacheline refill or an uncacheable fetch) is sent on the I$ miss interface, one at
//              a time.

`include "hpdcache_typedef.svh"

module cva6_hpdcache_icache
  import ariane_pkg::*;
  import wt_cache_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type icache_areq_t = logic,
    parameter type icache_arsp_t = logic,
    parameter type icache_dreq_t = logic,
    parameter type icache_drsp_t = logic,
    parameter type icache_req_t = logic,
    parameter type icache_rtrn_t = logic,
    parameter type exception_t = logic,
    parameter logic [CVA6Cfg.MEM_TID_WIDTH-1:0] RdTxId = 0
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic         flush_i,
    input  logic         en_i,
    output logic         miss_o,
    input  icache_areq_t areq_i,
    output icache_arsp_t areq_o,
    input  icache_dreq_t dreq_i,
    output icache_drsp_t dreq_o,
    input  logic         mem_rtrn_vld_i,
    input  icache_rtrn_t mem_rtrn_i,
    output logic         mem_data_req_o,
    input  logic         mem_data_ack_i,
    output icache_req_t  mem_data_o
);

  //  HPDcache configuration
  //  {{{
  localparam int unsigned WordWidth = 32;

  function automatic hpdcache_pkg::hpdcache_user_cfg_t icacheSetConfig();
    hpdcache_pkg::hpdcache_user_cfg_t userCfg;
    userCfg.nRequesters = 1;
    userCfg.paWidth = CVA6Cfg.PLEN;
    userCfg.wordWidth = WordWidth;
    userCfg.wordUserWidth = 1;
    userCfg.sets = (1 << CVA6Cfg.ICACHE_INDEX_WIDTH) / (CVA6Cfg.ICACHE_LINE_WIDTH / 8);
    userCfg.ways = CVA6Cfg.ICACHE_SET_ASSOC;
    userCfg.clWords = CVA6Cfg.ICACHE_LINE_WIDTH / WordWidth;
    userCfg.reqWords = CVA6Cfg.FETCH_WIDTH / WordWidth;
    userCfg.reqTransIdWidth = 2;
    userCfg.reqSrcIdWidth = 1;
    userCfg.victimSel = hpdcache_pkg::HPDCACHE_VICTIM_RANDOM;
    userCfg.dataWaysPerRamWord = (CVA6Cfg.ICACHE_SET_ASSOC < 128 / WordWidth) ?
                                 CVA6Cfg.ICACHE_SET_ASSOC : 128 / WordWidth;
    userCfg.dataSetsPerRam = userCfg.sets;
    userCfg.dataRamByteEnable = 1'b1;
    //  refills write 128 bits (or a fetch) per cycle in the data RAM
    userCfg.accessWords = (CVA6Cfg.FETCH_WIDTH > 128) ? CVA6Cfg.FETCH_WIDTH / WordWidth :
                                                        128 / WordWidth;
    //  one outstanding refill (the I$ miss interface handles one request at a time)
    userCfg.mshrSets = 1;
    userCfg.mshrWays = 2;
    userCfg.mshrWaysPerRamWord = 2;
    userCfg.mshrSetsPerRam = 1;
    userCfg.mshrRamByteEnable = 1'b1;
    userCfg.mshrUseRegbank = 1'b1;
    userCfg.cbufEntries = 2;
    userCfg.refillCoreRspFeedthrough = 1'b1;
    userCfg.refillFifoDepth = 2;
    //  read-only: no write buffer nor flush
    userCfg.wbufDirEntries = 1;
    userCfg.wbufDataEntries = 1;
    userCfg.wbufWords = 1;
    userCfg.wbufTimecntWidth = 3;
    userCfg.rtabEntries = 2;
    userCfg.flushEntries = 1;
    userCfg.flushFifoDepth = 1;
    userCfg.memAddrWidth = CVA6Cfg.AxiAddrWidth;
    userCfg.memIdWidth = 2;
    userCfg.memDataWidth = CVA6Cfg.ICACHE_LINE_WIDTH;
    userCfg.wtEn = 1'b0;
    userCfg.wbEn = 1'b0;
    userCfg.lowLatency = 1'b1;
    userCfg.userEn = 1'b0;
    userCfg.capAmoEn = 1'b0;
    userCfg.eccEn = CVA6Cfg.DcacheEccEnable;
    userCfg.eccScrubberEn = 1'b0;
    return userCfg;
  endfunction

  localparam hpdcache_pkg::hpdcache_user_cfg_t HPDcacheUserCfg = icacheSetConfig();
  localparam hpdcache_pkg::hpdcache_cfg_t HPDcacheCfg = hpdcache_pkg::hpdcacheBuildConfig(
      HPDcacheUserCfg
  );

  `HPDCACHE_USEREN_TYPEDEF_MEM_ATTR_T(hpdcache_mem_addr_t, hpdcache_mem_id_t, hpdcache_mem_data_t,
                                      hpdcache_mem_be_t, hpdcache_mem_user_t, HPDcacheCfg);
  `HPDCACHE_TYPEDEF_MEM_REQ_T(hpdcache_mem_req_t, hpdcache_mem_addr_t, hpdcache_mem_id_t);
  `HPDCACHE_USEREN_TYPEDEF_MEM_RESP_R_T(hpdcache_mem_resp_r_t, hpdcache_mem_id_t,
                                        hpdcache_mem_data_t, hpdcache_mem_user_t);
  `HPDCACHE_USEREN_TYPEDEF_MEM_REQ_W_T(hpdcache_mem_req_w_t, hpdcache_mem_data_t,
                                       hpdcache_mem_be_t, hpdcache_mem_user_t);
  `HPDCACHE_TYPEDEF_MEM_RESP_W_T(hpdcache_mem_resp_w_t, hpdcache_mem_id_t);

  `HPDCACHE_USEREN_TYPEDEF_REQ_ATTR_T(hpdcache_req_offset_t, hpdcache_data_word_t,
                                      hpdcache_data_be_t, hpdcache_req_data_t, hpdcache_req_be_t,
                                      hpdcache_req_sid_t, hpdcache_req_tid_t, hpdcache_tag_t,
                                      hpdcache_req_user_t, HPDcacheCfg);
  `HPDCACHE_USEREN_TYPEDEF_REQ_T(hpdcache_req_t, hpdcache_req_offset_t, hpdcache_req_data_t,
                                 hpdcache_req_be_t, hpdcache_req_sid_t, hpdcache_req_tid_t,
                                 hpdcache_tag_t, hpdcache_req_user_t);
  `HPDCACHE_USEREN_TYPEDEF_RSP_T(hpdcache_rsp_t, hpdcache_req_data_t, hpdcache_req_sid_t,
                                 hpdcache_req_tid_t, hpdcache_req_user_t);

  typedef logic [HPDcacheCfg.u.wbufTimecntWidth-1:0] hpdcache_wbuf_timecnt_t;
  typedef logic [HPDcacheCfg.nlineWidth-1:0] hpdcache_nline_t;

  localparam int unsigned OffsetWidth = HPDcacheCfg.reqOffsetWidth;
  //  }}}

  //  HPDcache
  //  {{{
  logic                 hpd_req_valid [1];
  logic                 hpd_req_ready [1];
  hpdcache_req_t        hpd_req       [1];
  logic                 hpd_req_abort [1];
  hpdcache_tag_t        hpd_req_tag   [1];
  hpdcache_pkg::hpdcache_pma_t hpd_req_pma [1];
  logic                 hpd_rsp_valid [1];
  hpdcache_rsp_t        hpd_rsp       [1];

  logic                 mem_req_read_ready, mem_req_read_valid;
  hpdcache_mem_req_t    mem_req_read;
  logic                 mem_resp_read_ready, mem_resp_read_valid;
  hpdcache_mem_resp_r_t mem_resp_read;

  hpdcache #(
      .HPDcacheCfg          (HPDcacheCfg),
      .wbuf_timecnt_t       (hpdcache_wbuf_timecnt_t),
      .hpdcache_tag_t       (hpdcache_tag_t),
      .hpdcache_data_word_t (hpdcache_data_word_t),
      .hpdcache_data_be_t   (hpdcache_data_be_t),
      .hpdcache_req_offset_t(hpdcache_req_offset_t),
      .hpdcache_req_user_t  (hpdcache_req_user_t),
      .hpdcache_req_data_t  (hpdcache_req_data_t),
      .hpdcache_req_be_t    (hpdcache_req_be_t),
      .hpdcache_req_sid_t   (hpdcache_req_sid_t),
      .hpdcache_req_tid_t   (hpdcache_req_tid_t),
      .hpdcache_req_t       (hpdcache_req_t),
      .hpdcache_rsp_t       (hpdcache_rsp_t),
      .hpdcache_mem_addr_t  (hpdcache_mem_addr_t),
      .hpdcache_mem_id_t    (hpdcache_mem_id_t),
      .hpdcache_mem_data_t  (hpdcache_mem_data_t),
      .hpdcache_mem_be_t    (hpdcache_mem_be_t),
      .hpdcache_mem_req_t   (hpdcache_mem_req_t),
      .hpdcache_mem_req_w_t (hpdcache_mem_req_w_t),
      .hpdcache_mem_resp_r_t(hpdcache_mem_resp_r_t),
      .hpdcache_mem_resp_w_t(hpdcache_mem_resp_w_t)
  ) i_hpdcache (
      .clk_i,
      .rst_ni,

      .wbuf_flush_i(1'b0),

      .core_req_valid_i(hpd_req_valid),
      .core_req_ready_o(hpd_req_ready),
      .core_req_i      (hpd_req),
      .core_req_abort_i(hpd_req_abort),
      .core_req_tag_i  (hpd_req_tag),
      .core_req_pma_i  (hpd_req_pma),

      .core_rsp_valid_o(hpd_rsp_valid),
      .core_rsp_o      (hpd_rsp),

      .mem_req_read_ready_i(mem_req_read_ready),
      .mem_req_read_valid_o(mem_req_read_valid),
      .mem_req_read_o      (mem_req_read),

      .mem_resp_read_ready_o(mem_resp_read_ready),
      .mem_resp_read_valid_i(mem_resp_read_valid),
      .mem_resp_read_i      (mem_resp_read),

      .mem_resp_read_inval_i      (1'b0),
      .mem_resp_read_inval_nline_i(hpdcache_nline_t'(0)),

      //  read-only cache: no writes to memory
      .mem_req_write_ready_i(1'b1),
      .mem_req_write_valid_o(  /* unused */),
      .mem_req_write_o      (  /* unused */),

      .mem_req_write_data_ready_i(1'b1),
      .mem_req_write_data_valid_o(  /* unused */),
      .mem_req_write_data_o      (  /* unused */),

      .mem_resp_write_ready_o(  /* unused */),
      .mem_resp_write_valid_i(1'b0),
      .mem_resp_write_i      ('0),

      .evt_cache_write_miss_o (  /* unused */),
      .evt_cache_read_miss_o  (  /* unused */),
      .evt_cache_dir_unc_err_o(  /* unused */),
      .evt_cache_dir_cor_err_o(  /* unused */),
      .evt_cache_dat_unc_err_o(  /* unused */),
      .evt_cache_dat_cor_err_o(  /* unused */),
      .evt_scrub_complete_o   (  /* unused */),
      .evt_uncached_req_o     (  /* unused */),
      .evt_cmo_req_o          (  /* unused */),
      .evt_write_req_o        (  /* unused */),
      .evt_read_req_o         (  /* unused */),
      .evt_prefetch_req_o     (  /* unused */),
      .evt_req_on_hold_o      (  /* unused */),
      .evt_rtab_rollback_o    (  /* unused */),
      .evt_stall_refill_o     (  /* unused */),
      .evt_stall_o            (  /* unused */),

      .wbuf_empty_o(  /* unused */),

      .cfg_enable_i                       (1'b1),
      .cfg_wbuf_threshold_i               (hpdcache_wbuf_timecnt_t'(0)),
      .cfg_wbuf_reset_timecnt_on_write_i  (1'b1),
      .cfg_wbuf_sequential_waw_i          (1'b0),
      .cfg_wbuf_inhibit_write_coalescing_i(1'b0),
      .cfg_prefetch_updt_plru_i           (1'b1),
      .cfg_error_on_cacheable_amo_i       (1'b0),
      .cfg_rtab_single_entry_i            (1'b0),
      .cfg_default_wb_i                   (1'b0),
      .cfg_scrub_enable_i                 (1'b0),
      .cfg_scrub_period_i                 (6'd0),
      .cfg_scrub_restart_i                (1'b0)
  );
  //  }}}

  //  Frontend requests
  //  {{{
  typedef enum logic [3:0] {
    IDLE,         // ready for a request
    LOOKUP,       // HPDcache stage 1 of a request: translation (or saved address), tag or abort
    WAIT_TRANS,   // request aborted: waiting for the translation
    REISSUE,      // translation available: sending the request again
    WAIT_RSP,     // miss or uncacheable fetch: waiting for the response
    KILL_ATRANS,  // killed while waiting for the translation: wait for it to complete
    FLUSH_REQ,    // sending the invalidation of the whole cache
    FLUSH_WAIT    // waiting for the invalidation to complete
  } state_e;

  state_e state_d, state_q;

  logic cache_en_d, cache_en_q;  // cache is enabled
  logic flush_d, flush_q;  // pending flush
  logic [CVA6Cfg.VLEN-1:0] vaddr_d, vaddr_q;
  logic [CVA6Cfg.DIIIDLEN-1:0] dii_id_d, dii_id_q;
  logic [CVA6Cfg.PLEN-1:0] paddr_d, paddr_q;  // translated address (when the request is reissued)
  logic paddr_valid_d, paddr_valid_q;  // the stage 1 request uses paddr_q, not the translation
  logic killed_d, killed_q;  // the outstanding request was killed (its response is dropped)
  hpdcache_req_tid_t tid_d, tid_q;  // transaction ID of the outstanding request

  logic [CVA6Cfg.PLEN-1:0] lookup_paddr;
  logic lookup_paddr_valid;
  logic lookup_paddr_nc;
  logic lookup_addr_ni;
  logic rsp_valid;
  logic send_req;  // send a fetch request to the HPDcache
  logic reissue;  // the request sent is the outstanding one again (with its saved translation)
  logic accept_req;  // the outstanding fetch is complete (or killed): accept a new one
  hpdcache_req_offset_t req_offset;

  //  the translated address of the request in stage 1: from the translation, or saved when the
  //  request is sent again
  assign lookup_paddr = paddr_valid_q ? paddr_q : areq_i.fetch_paddr;
  assign lookup_paddr_valid = paddr_valid_q || areq_i.fetch_valid;

  //  noncacheable if request goes to I/O space, or if cache is disabled
  assign lookup_paddr_nc = !cache_en_q || !config_pkg::is_inside_cacheable_regions(
      CVA6Cfg, {{64 - CVA6Cfg.PLEN{1'b0}}, lookup_paddr}
  );
  assign lookup_addr_ni = config_pkg::is_inside_nonidempotent_regions(
      CVA6Cfg, {{64 - CVA6Cfg.PLEN{1'b0}}, lookup_paddr}
  );

  //  response to the outstanding request (aborted responses are not responses to fetches)
  assign rsp_valid = hpd_rsp_valid[0] && !hpd_rsp[0].aborted && (hpd_rsp[0].tid == tid_q);

  //  request to the HPDcache: a fetch (virtually indexed), or the invalidation of the cache
  assign req_offset = hpdcache_req_offset_t'(
      ((send_req && !reissue) ? dreq_i.vaddr : vaddr_q) >> CVA6Cfg.FETCH_ALIGN_BITS
      << CVA6Cfg.FETCH_ALIGN_BITS);

  always_comb begin : hpd_req_comb
    hpd_req[0] = '0;
    hpd_req[0].addr_offset = req_offset;
    hpd_req[0].op = (state_q == FLUSH_REQ) ? hpdcache_pkg::HPDCACHE_REQ_CMO_INVAL_ALL :
                                             hpdcache_pkg::HPDCACHE_REQ_LOAD;
    hpd_req[0].be = '1;
    hpd_req[0].size = hpdcache_pkg::hpdcache_req_size_t'($clog2(CVA6Cfg.FETCH_WIDTH / 8));
    hpd_req[0].sid = '0;
    hpd_req[0].tid = tid_d;
    hpd_req[0].need_rsp = 1'b1;
    //  the invalidation of the whole cache has no address
    hpd_req[0].phys_indexed = (state_q == FLUSH_REQ);
    hpd_req[0].addr_tag = '0;
    hpd_req[0].pma.uncacheable = 1'b0;
    hpd_req[0].pma.io = 1'b0;
    hpd_req[0].pma.wr_policy_hint = hpdcache_pkg::HPDCACHE_WR_POLICY_AUTO;
  end

  //  stage 1 of a fetch: tag and attributes of its translated address
  assign hpd_req_tag[0] = hpdcache_tag_t'(lookup_paddr >> OffsetWidth);
  assign hpd_req_pma[0].uncacheable = lookup_paddr_nc;
  assign hpd_req_pma[0].io = 1'b0;
  assign hpd_req_pma[0].wr_policy_hint = hpdcache_pkg::HPDCACHE_WR_POLICY_AUTO;

  //  address translation
  assign areq_o.fetch_vaddr = (vaddr_q >> CVA6Cfg.FETCH_ALIGN_BITS) << CVA6Cfg.FETCH_ALIGN_BITS;
  assign areq_o.fetch_exception = '0;

  //  response to the frontend
  assign dreq_o.vaddr = vaddr_q;
  assign dreq_o.dii_id = dii_id_q;
  assign dreq_o.data = hpd_rsp[0].rdata[0 +: CVA6Cfg.FETCH_WIDTH];
  assign dreq_o.user = '0;

  always_comb begin : p_fsm
    state_d = state_q;
    //  disabling the cache is always possible, enabling it needs to go via a flush
    cache_en_d = cache_en_q & en_i;
    flush_d = flush_q | flush_i;
    vaddr_d = vaddr_q;
    dii_id_d = dii_id_q;
    paddr_d = paddr_q;
    paddr_valid_d = paddr_valid_q;
    killed_d = killed_q;
    tid_d = tid_q;

    dreq_o.ready = 1'b0;
    dreq_o.valid = 1'b0;
    dreq_o.ex = '0;
    areq_o.fetch_req = 1'b0;
    miss_o = 1'b0;

    hpd_req_valid[0] = 1'b0;
    hpd_req_abort[0] = 1'b0;
    send_req = 1'b0;
    reissue = 1'b0;
    accept_req = 1'b0;

    //  A request is accepted in the cycle the previous one completes (or is killed), so that a
    //  new lookup can start every cycle.
    unique case (state_q)
      //  wait for a request
      IDLE: begin
        if (flush_d || (en_i && !cache_en_q)) begin
          state_d = FLUSH_REQ;
        end else begin
          accept_req = 1'b1;
        end
      end

      //  stage 1 of a request: send its tag, or abort it
      LOOKUP: begin
        areq_o.fetch_req = !paddr_valid_q;
        if (dreq_i.kill_s2 || flush_d) begin
          //  killed: abort it, and wait for the translation if it was requested and is not
          //  complete
          hpd_req_abort[0] = 1'b1;
          paddr_valid_d = 1'b0;
          if (!paddr_valid_q && !areq_i.fetch_valid) begin
            state_d = KILL_ATRANS;
          end else begin
            state_d = IDLE;
            accept_req = 1'b1;
          end
        end else if (!paddr_valid_q && areq_i.fetch_valid && areq_i.fetch_exception.valid) begin
          //  exception during the translation: respond with the exception
          hpd_req_abort[0] = 1'b1;
          dreq_o.valid = 1'b1;
          dreq_o.ex = areq_i.fetch_exception;
          state_d = IDLE;
          accept_req = 1'b1;
        end else if (!lookup_paddr_valid ||
                     (dreq_i.spec && CVA6Cfg.NonIdemPotenceEn && lookup_addr_ni)) begin
          //  translation not available (or speculative fetch to a non-idempotent region): abort
          //  the request, and send it again once possible
          hpd_req_abort[0] = 1'b1;
          if (lookup_paddr_valid) begin
            paddr_d = lookup_paddr;
            paddr_valid_d = 1'b1;
          end
          state_d = WAIT_TRANS;
        end else begin
          //  tag sent: a hit responds in this cycle, otherwise wait for the response
          paddr_valid_d = 1'b0;
          if (rsp_valid) begin
            dreq_o.valid = 1'b1;
            state_d = IDLE;
            accept_req = 1'b1;
          end else begin
            miss_o = !lookup_paddr_nc;
            killed_d = 1'b0;
            state_d = WAIT_RSP;
          end
        end
      end

      //  wait for the translation (or for the fetch to be non-speculative)
      WAIT_TRANS: begin
        areq_o.fetch_req = !paddr_valid_q;
        if (dreq_i.kill_s2 || flush_d) begin
          paddr_valid_d = 1'b0;
          if (!paddr_valid_q && !areq_i.fetch_valid) begin
            state_d = KILL_ATRANS;
          end else begin
            state_d = IDLE;
            accept_req = 1'b1;
          end
        end else if (!paddr_valid_q && areq_i.fetch_valid && areq_i.fetch_exception.valid) begin
          dreq_o.valid = 1'b1;
          dreq_o.ex = areq_i.fetch_exception;
          state_d = IDLE;
          accept_req = 1'b1;
        end else if (lookup_paddr_valid) begin
          //  send the request again as soon as possible, with the translation saved for stage 1
          paddr_d = lookup_paddr;
          paddr_valid_d = 1'b1;
          if (!(dreq_i.spec && CVA6Cfg.NonIdemPotenceEn && lookup_addr_ni)) begin
            send_req = 1'b1;
            reissue = 1'b1;
          end
        end
      end

      //  send the request again, with the saved translation (the HPDcache was not ready)
      REISSUE: begin
        if (dreq_i.kill_s2 || flush_d) begin
          paddr_valid_d = 1'b0;
          state_d = IDLE;
          accept_req = 1'b1;
        end else begin
          send_req = 1'b1;
          reissue = 1'b1;
        end
      end

      //  miss or uncacheable fetch: wait for the response
      WAIT_RSP: begin
        if (dreq_i.kill_s2 || flush_d) begin
          killed_d = 1'b1;
        end
        if (rsp_valid) begin
          dreq_o.valid = !(killed_d);
          killed_d = 1'b0;
          state_d = IDLE;
          accept_req = 1'b1;
        end
      end

      //  killed while waiting for the translation: wait for it to complete
      KILL_ATRANS: begin
        areq_o.fetch_req = 1'b1;
        if (areq_i.fetch_valid) begin
          state_d = IDLE;
          accept_req = 1'b1;
        end
      end

      //  invalidate the whole cache
      FLUSH_REQ: begin
        hpd_req_valid[0] = 1'b1;
        tid_d = tid_q + 1;
        if (hpd_req_ready[0]) begin
          state_d = FLUSH_WAIT;
        end
      end
      FLUSH_WAIT: begin
        if (rsp_valid) begin
          flush_d = 1'b0;
          cache_en_d = en_i;
          state_d = IDLE;
        end
      end

      default: state_d = IDLE;
    endcase

    //  accept a new request, unless the cache has to be flushed (or invalidated to be enabled)
    if (accept_req && !(flush_d || (en_i && !cache_en_q))) begin
      dreq_o.ready = hpd_req_ready[0];
      if (dreq_i.req && !dreq_i.kill_s1) begin
        send_req = 1'b1;
      end
    end

    //  send a (new or reissued) fetch request
    if (send_req) begin
      hpd_req_valid[0] = 1'b1;
      if (!reissue) begin
        vaddr_d = dreq_i.vaddr;
        dii_id_d = dreq_i.dii_id;
      end
      tid_d = tid_q + 1;
      if (hpd_req_ready[0]) begin
        state_d = LOOKUP;
      end else begin
        tid_d = tid_q;
        state_d = reissue ? REISSUE : IDLE;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if (!rst_ni) begin
      state_q       <= IDLE;
      cache_en_q    <= 1'b0;
      flush_q       <= 1'b0;
      vaddr_q       <= '0;
      dii_id_q      <= '0;
      paddr_q       <= '0;
      paddr_valid_q <= 1'b0;
      killed_q      <= 1'b0;
      tid_q         <= '0;
    end else begin
      state_q       <= state_d;
      cache_en_q    <= cache_en_d;
      flush_q       <= flush_d;
      vaddr_q       <= vaddr_d;
      dii_id_q      <= dii_id_d;
      paddr_q       <= paddr_d;
      paddr_valid_q <= paddr_valid_d;
      killed_q      <= killed_d;
      tid_q         <= tid_d;
    end
  end
  //  }}}

  //  Memory interface: HPDcache memory reads on the I$ miss interface, one at a time
  //  {{{
  logic                    mem_pending_q;
  hpdcache_mem_id_t        mem_id_q;
  logic [CVA6Cfg.PLEN-1:0] mem_addr_q;
  logic                    mem_nc_q;
  logic                    mem_rsp_valid_q;
  hpdcache_mem_data_t      mem_rsp_data_q;

  //  an uncacheable fetch reads the 64-bit word holding it
  assign mem_data_req_o = mem_req_read_valid && !mem_pending_q;
  assign mem_req_read_ready = mem_data_ack_i && !mem_pending_q;
  assign mem_data_o.paddr = mem_req_read.mem_req_cacheable ?
      CVA6Cfg.PLEN'(mem_req_read.mem_req_addr) :
      CVA6Cfg.PLEN'(mem_req_read.mem_req_addr) & ~CVA6Cfg.PLEN'(7);
  assign mem_data_o.nc = !mem_req_read.mem_req_cacheable;
  assign mem_data_o.tid = RdTxId;
  assign mem_data_o.way = '0;

  //  the response of the I$ miss interface is a cacheline, or the 64-bit word of an uncacheable
  //  fetch (right-aligned), which the HPDcache expects at its position in the cacheline
  always_ff @(posedge clk_i or negedge rst_ni) begin : mem_ff
    if (!rst_ni) begin
      mem_pending_q   <= 1'b0;
      mem_id_q        <= '0;
      mem_addr_q      <= '0;
      mem_nc_q        <= 1'b0;
      mem_rsp_valid_q <= 1'b0;
      mem_rsp_data_q  <= '0;
    end else begin
      if (mem_data_req_o && mem_data_ack_i) begin
        mem_pending_q <= 1'b1;
        mem_id_q      <= mem_req_read.mem_req_id;
        mem_addr_q    <= CVA6Cfg.PLEN'(mem_req_read.mem_req_addr);
        mem_nc_q      <= !mem_req_read.mem_req_cacheable;
      end
      if (mem_rtrn_vld_i && (mem_rtrn_i.rtype == ICACHE_IFILL_ACK) && mem_pending_q) begin
        mem_rsp_valid_q <= 1'b1;
        if (mem_nc_q) begin
          mem_rsp_data_q <= hpdcache_mem_data_t'(mem_rtrn_i.data[63:0]) <<
                            ({mem_addr_q[$clog2(CVA6Cfg.ICACHE_LINE_WIDTH/8)-1:3], 6'b0});
        end else begin
          mem_rsp_data_q <= hpdcache_mem_data_t'(mem_rtrn_i.data);
        end
      end else if (mem_resp_read_ready) begin
        if (mem_rsp_valid_q) mem_pending_q <= 1'b0;
        mem_rsp_valid_q <= 1'b0;
      end
    end
  end

  //  bus errors on fetches are not reported (as with cva6_icache)
  assign mem_resp_read_valid = mem_rsp_valid_q;
  always_comb begin : mem_resp_comb
    mem_resp_read = '0;
    mem_resp_read.mem_resp_r_error = hpdcache_pkg::HPDCACHE_MEM_RESP_OK;
    mem_resp_read.mem_resp_r_id = mem_id_q;
    mem_resp_read.mem_resp_r_data = mem_rsp_data_q;
    mem_resp_read.mem_resp_r_last = 1'b1;
  end
  //  }}}

  //  Assertions
  //  {{{
  //  pragma translate_off
  initial begin : initial_assertions
    assert (CVA6Cfg.ICACHE_INDEX_WIDTH <= 12)
    else $fatal(1, "[l1 icache] cache index width can be maximum 12bit since VM uses 4kB pages");
    assert (!CVA6Cfg.FETCH_USER_EN)
    else $fatal(1, "[l1 icache] fetch user bits are not supported by the HPDcache I$");
    assert (CVA6Cfg.ICACHE_LINE_WIDTH >= 64)
    else $fatal(1, "[l1 icache] the cacheline shall be at least 64 bits");
  end
  //  pragma translate_on
  //  }}}

endmodule : cva6_hpdcache_icache
