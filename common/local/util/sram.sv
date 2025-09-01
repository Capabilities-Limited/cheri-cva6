// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba    <zarubaf@iis.ee.ethz.ch>, ETH Zurich
//         Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 15.08.2018
// Description: SRAM wrapper for FPGA (requires the fpga-support submodule)
//
// Note: the wrapped module contains two different implementations for
// ALTERA and XILINX tools, since these follow different coding styles for
// inferrable RAMS with byte enable. define `FPGA_TARGET_XILINX or
// `FPGA_TARGET_ALTERA in your build environment (default is ALTERA)

module sram #(
    parameter DATA_WIDTH = 64,
    parameter USER_WIDTH = 1,
    parameter USER_EN    = 0,
    parameter NUM_WORDS  = 1024,
    parameter SIM_INIT   = "none",
    parameter OUT_REGS   = 0     // enables output registers in FPGA macro (read lat = 2)
)(
   input  logic                          clk_i,
   input  logic                          rst_ni,
   input  logic                          req_i,
   input  logic                          we_i,
   input  logic [$clog2(NUM_WORDS)-1:0]  addr_i,
   input  logic [USER_WIDTH-1:0]         wuser_i,
   input  logic [DATA_WIDTH-1:0]         wdata_i,
   input  logic [(DATA_WIDTH+7)/8-1:0]   be_i,
   output logic [USER_WIDTH-1:0]         ruser_o,
   output logic [DATA_WIDTH-1:0]         rdata_o
);

localparam DATA_WIDTH_ALIGNED = ((DATA_WIDTH+63)/64)*64;
localparam USER_WIDTH_ALIGNED = ((USER_WIDTH+63)/64)*64;
localparam DATA_BE_WIDTH_ALIGNED = DATA_WIDTH_ALIGNED/8;

//if (USER_WIDTH_ALIGNED > DATA_WIDTH_ALIGNED)
//    $fatal(1, "[sram] USER_WIDTH greater than DATA_WIDTH not yet supported");
//else if ((DATA_WIDTH_ALIGNED*2)/USER_WIDTH_ALIGNED >= 2) begin
    // If there is at least one bit of USER for each byte of DATA,
    // we can simply adjust the USER_BYTE_WIDTH.
//    localparam USER_BYTE_WIDTH = DATA_WIDTH_ALIGNED/USER_WIDTH_ALIGNED;
//    localparam USER_BE_WIDTH_ALIGNED = DATA_BE_WIDTH_ALIGNED;
//end else begin
    // Otherwise, we have one "byte enable" per bit and must fold
    // the data byte enables down.
    localparam DATA_BE_WIDTH = (DATA_WIDTH+7)/8;
    localparam USER_BYTE_WIDTH = (DATA_WIDTH/USER_WIDTH >= 8) ? 1 : 8/(DATA_WIDTH/USER_WIDTH);
    localparam USER_BE_WIDTH = (USER_BYTE_WIDTH==1) ?
                               USER_WIDTH :
                               DATA_BE_WIDTH;
//end
localparam USER_BE_WIDTH_ALIGNED = USER_WIDTH_ALIGNED/USER_BYTE_WIDTH;

function automatic logic [USER_BE_WIDTH-1:0] fold_data_be
  (input logic [DATA_BE_WIDTH-1:0] in);

  // Group size: number of DATA_BE_WIDTH bits that map to each narrow bit
  localparam int GROUP = (USER_EN) ? (DATA_BE_WIDTH / USER_BE_WIDTH) : 1;
  logic [USER_BE_WIDTH-1:0] out;

  begin
    for (int i = 0; i < USER_BE_WIDTH; i++) begin
      out[i] = |in[i*GROUP +: GROUP];  
      // "i*GROUP +: GROUP" selects a slice of GROUP bits
      // "|" reduces them with OR
    end
    return out;
  end
endfunction

logic [DATA_WIDTH_ALIGNED-1:0]  wdata_aligned;
logic [USER_WIDTH_ALIGNED-1:0]  wuser_aligned;
logic [DATA_BE_WIDTH_ALIGNED-1:0]  data_be_aligned;
logic [USER_BE_WIDTH_ALIGNED-1:0]  user_be_aligned;
logic [DATA_WIDTH_ALIGNED-1:0]  rdata_aligned;
logic [USER_WIDTH_ALIGNED-1:0]  ruser_aligned;

// align to 64 bits for inferrable macro below
always_comb begin : p_align
    wdata_aligned                    ='0;
    wuser_aligned                    ='0;
    data_be_aligned ='0;
    wdata_aligned[DATA_WIDTH-1:0] = wdata_i;
    wuser_aligned[USER_WIDTH-1:0] = wuser_i;
    data_be_aligned[DATA_BE_WIDTH-1:0] = be_i;
    user_be_aligned[USER_BE_WIDTH-1:0] = fold_data_be(be_i);

    rdata_o = rdata_aligned[DATA_WIDTH-1:0];
    ruser_o = ruser_aligned[USER_WIDTH-1:0];
end

  for (genvar k = 0; k<(DATA_WIDTH+63)/64; k++) begin : gen_cut
      // unused byte-enable segments (8bits) are culled by the tool
      tc_sram_wrapper #(
        .NumWords(NUM_WORDS),           // Number of Words in data array
        .DataWidth(64),                 // Data signal width
        .ByteWidth(32'd8),              // Width of a data byte
        .NumPorts(32'd1),               // Number of read and write ports
        .Latency(32'd1),                // Latency when the read data is available
        .SimInit(SIM_INIT),             // Simulation initialization
        .PrintSimCfg(1'b0)              // Print configuration
      ) i_tc_sram_wrapper (
          .clk_i    ( clk_i                     ),
          .rst_ni   ( rst_ni                    ),
          .req_i    ( req_i                     ),
          .we_i     ( we_i                      ),
          .be_i     ( data_be_aligned[k*8 +: 8]      ),
          .wdata_i  ( wdata_aligned[k*64 +: 64] ),
          .addr_i   ( addr_i                    ),
          .rdata_o  ( rdata_aligned[k*64 +: 64] )
      );
  end
  for (genvar k = 0; k < (USER_WIDTH + 63) / 64; k++) begin : gen_user_cut
    if (USER_EN > 0) begin : gen_mem_user
      tc_sram_wrapper #(
          .NumWords   (NUM_WORDS),  // Number of Words in data array
          .DataWidth  (64),         // Data signal width
          .ByteWidth  (USER_BYTE_WIDTH), // Width of a data byte
          .NumPorts   (32'd1),      // Number of read and write ports
          .Latency    (32'd1),      // Latency when the read data is available
          .SimInit    (SIM_INIT),   // Simulation initialization
          .PrintSimCfg(1'b0)        // Print configuration
      ) i_tc_sram_wrapper_user (
          .clk_i  (clk_i),
          .rst_ni (rst_ni),
          .req_i  (req_i),
          .we_i   (we_i),
          .be_i   (user_be_aligned[k*(64/USER_BYTE_WIDTH)+:(64/USER_BYTE_WIDTH)]),
          .wdata_i(wuser_aligned[k*64+:64]),
          .addr_i (addr_i),
          .rdata_o(ruser_aligned[k*64+:64])
      );
    end else begin
      assign ruser_aligned[k*64+:64] = '0;
    end
  end
endmodule : sram
