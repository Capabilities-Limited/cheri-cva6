
// Copyright 2025 Bruno Sá and Zero-Day Labs.
// Copyright 2025 Capabilities Limited.
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at

//   http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
//
// Copyright 2025 Capabilities Limited

#include "verilator.h"
#include "verilated.h"
#include "Variane_testharness_dii.h"
#if (VERILATOR_VERSION_INTEGER >= 5000000)
  // Verilator v5 adds $root wrapper that provides rootp pointer.
  #include "Variane_testharness_dii___024root.h"
#endif
#if VM_TRACE_FST
#include "verilated_fst_c.h"
#else
#include "verilated_vcd_c.h"
#endif
#include "Variane_testharness_dii__Dpi.h"

#include <stdio.h>
#include <iostream>
#include <iomanip>
#include <string>
#include <getopt.h>
#include <ctime>
#include <signal.h>
#include <unistd.h>
#include <vector>

//Exclude DII getters as they are defined in a verilator header for DPI
#define exclude_dii_getters
#include <rvfi_dii_utils.h>

#define DII_ID_WIDTH 6
#define DII_ID_COUNT (1 << DII_ID_WIDTH)

// This software is heavily based on Rocket Chip
// Checkout this awesome project:
// https://github.com/freechipsproject/rocket-chip/

// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.
static vluint64_t main_time = 0;

static const char *verilog_plusargs[] = {"time_out"};

static int current_test_dii_start = 0;

// Routine to fetch intructions from the Vengine
rvfi_pkt_t readRVFI_0(Variane_testharness_dii *top);
rvfi_pkt_t readRVFI_1(Variane_testharness_dii *top);
void readTrace(Variane_testharness_dii *top, unsigned int *rvfi_id);
void sendReset(unsigned int rvfi_id);

// Called by $time in Verilog converts to double, to match what SystemC does
double sc_time_stamp () {
    return main_time;
}

static void usage(const char * program_name) {
  printf("Usage: %s [EMULATOR OPTION]... [VERILOG PLUSARG]... [HOST OPTION]... BINARY [TARGET OPTION]...\n",
         program_name);
  fputs("\
Run a BINARY on the Ariane emulator.\n\
\n\
Mandatory arguments to long options are mandatory for short options too.\n\
\n\
EMULATOR OPTIONS\n\
  -r, --rbb-port=PORT      Use PORT for remote bit bang (with OpenOCD and GDB) \n\
                           If not specified, a random port will be chosen\n\
                           automatically.\n\
", stdout);
#if VM_TRACE == 0
  fputs("\
\n\
EMULATOR DEBUG OPTIONS (only supported in debug build -- try `make debug`)\n",
        stdout);
#endif
  fputs("\
  -v, --vcd=FILE,          Write vcd trace to FILE (or '-' for stdout)\n\
  -f, --fst=FILE,          Write fst trace to FILE\n\
", stdout);
  // fputs("\n" PLUSARG_USAGE_OPTIONS, stdout);
  printf("\n"
"EXAMPLES\n"
"  - run a bare metal test:\n"
"    %s $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-add\n"
"  - run a bare metal test showing cycle-by-cycle information:\n"
"    %s spike-dasm < trace_core_00_0.dasm > trace.out\n"
#if VM_TRACE
"  - run a bare metal test to generate a VCD waveform:\n"
"    %s -v rv64ui-p-add.vcd $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-add\n"
"  - run a bare metal test to generate an FST waveform:\n"
"    %s -f rv64ui-p-add.fst $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-add\n"
#endif
  , program_name, program_name);
}

int main(int argc, char **argv) {
  bool verbose;
  int ret = 0;
#if VM_TRACE
  FILE * vcdfile = NULL;
  char * fst_fname = NULL;
  uint64_t start = 0;
#endif
  int verilog_plusargs_legal = 1;

  char* socket_name = NULL;
  int socket_default_port = -1;

  while (1) {
    static struct option long_options[] = {
      {"help",        no_argument,       0, 'h' },
      {"verbose",     no_argument,       0, 'V' },
#if VM_TRACE
      {"vcd",         required_argument, 0, 'v' },
      {"dump-start",  required_argument, 0, 'x' },
      {"fst",         required_argument, 0, 'f' },
#endif
      {"socket-name",         required_argument, 0, 'q' },
      {"socket-default-port",  required_argument, 0, 'w' },
    };
    int option_index = 0;
#if VM_TRACE
    int c = getopt_long(argc, argv, "-hv:f:Vx:q:w:", long_options, &option_index);
#else
    int c = getopt_long(argc, argv, "-hV:q:w:", long_options, &option_index);
#endif
    if (c == -1) break;
 retry:
    switch (c) {
      // Process long and short EMULATOR options
      case '?': usage(argv[0]);             return 1;
      case 'h': usage(argv[0]);             return 0;
      case 'V': verbose = true;             break;
      case 'q': {
        socket_name = strdup(optarg);
        break;
      }
      case 'w': socket_default_port = atoi(optarg); break;
#if VM_TRACE
      case 'v': {
        vcdfile = strcmp(optarg, "-") == 0 ? stdout : fopen(optarg, "w");
        if (!vcdfile) {
          std::cerr << "Unable to open " << optarg << " for VCD write\n";
          return 1;
        }
        break;
      }
      case 'f': {
        fst_fname = optarg;
        break;
      }
      case 'x': start = atoll(optarg);      break;
#endif
      // Process legacy '+' EMULATOR arguments by replacing them with
      // their getopt equivalents
      case 1: {
        std::string arg = optarg;
        if (arg.substr(0, 1) != "+") {
          optind--;
          goto done_processing;
        }
        if (arg == "+verbose")
          c = 'V';
#if VM_TRACE
        else if (arg.substr(0, 12) == "+dump-start=") {
          c = 'x';
          optarg = optarg+12;
        }
#endif
        // If we don't find a legacy '+' EMULATOR argument, it still could be
        // a VERILOG_PLUSARG and not an error.
        else if (verilog_plusargs_legal) {
          const char ** plusarg = &verilog_plusargs[0];
          int legal_verilog_plusarg = 0;
          while (*plusarg && (legal_verilog_plusarg == 0)){
            if (arg.substr(1, strlen(*plusarg)) == *plusarg) {
              legal_verilog_plusarg = 1;
            }
            plusarg ++;
          }
          if (!legal_verilog_plusarg) {
            verilog_plusargs_legal = 0;
          } else {
            c = 'P';
          }
          goto retry;
        }
        else {
          std::cerr << argv[0] << ": invalid plus-arg (Verilog or HTIF) \""
                    << arg << "\"\n";
          c = '?';
        }
        goto retry;
      }
      case 'P': break; // Nothing to do here, Verilog PlusArg
      default:
        c = '?';
        goto retry;
    }
  }

done_processing:
  const char *vcd_file = NULL;
  Verilated::commandArgs(argc, argv);

  Variane_testharness_dii* top(new Variane_testharness_dii);

#if VM_TRACE
  Verilated::traceEverOn(true); // Verilator must compute traced signals
#if VM_TRACE_FST
  std::unique_ptr<VerilatedFstC> tfp(new VerilatedFstC());
  if (fst_fname) {
    std::cerr << "Starting FST waveform dump into file '" << fst_fname << "'...\n";
    top->trace(tfp.get(), 99);  // Trace 99 levels of hierarchy
    tfp->open(fst_fname);
  }
  else
    std::cerr << "No explicit FST file name supplied, using RTL defaults.\n";
#else
  std::unique_ptr<VerilatedVcdFILE> vcdfd(new VerilatedVcdFILE(vcdfile));
  std::unique_ptr<VerilatedVcdC> tfp(new VerilatedVcdC(vcdfd.get()));
  if (vcdfile) {
    std::cerr << "Starting VCD waveform dump ...\n";
    top->trace(tfp.get(), 99);  // Trace 99 levels of hierarchy
    tfp->open("");
  }
  else
    std::cerr << "No explicit VCD file name supplied, using RTL defaults.\n";
#endif
#endif


  rvfi_dii_bridge_rst(DII_ID_WIDTH);

  for (int i = 0; i < 10; i++) {
    top->rst_ni = 0;
    top->clk_i = 0;
    top->rtc_i = 0;
    top->eval();
    fflush(stdout);
#if VM_TRACE
    if (vcdfile || fst_fname)
      tfp->dump(static_cast<vluint64_t>(main_time * 2));
#endif
    top->clk_i = 1;
    top->eval();
    fflush(stdout);
#if VM_TRACE
    if (vcdfile || fst_fname)
      tfp->dump(static_cast<vluint64_t>(main_time * 2 + 1));
#endif
    main_time++;
  }
  top->rst_ni = 1;
  // Preload memory.
#if (VERILATOR_VERSION_INTEGER >= 5000000)
  // Verilator v5: Use rootp pointer and .data() accessor.
#define MEM0 top->rootp->ariane_testharness_dii__DOT__i_sram__DOT__gen_cut__BRA__0__KET____DOT__i_tc_sram_wrapper__DOT__i_tc_sram__DOT__sram.m_storage
#define MEM1 top->rootp->ariane_testharness_dii__DOT__i_sram__DOT__gen_cut__BRA__1__KET____DOT__i_tc_sram_wrapper__DOT__i_tc_sram__DOT__sram.m_storage
#else
  // Verilator v4
#define MEM0 top->ariane_testharness_dii__DOT__i_sram__DOT__gen_cut__BRA__0__KET____DOT__i_tc_sram_wrapper__DOT__i_tc_sram__DOT__sram
#define MEM1 top->ariane_testharness_dii__DOT__i_sram__DOT__gen_cut__BRA__1__KET____DOT__i_tc_sram_wrapper__DOT__i_tc_sram__DOT__sram
#endif
  long long addr;
  long long len;

  size_t mem_size = 0x900000;
  unsigned int traces_count = 0;
  // instruction
  bool eof_trace = false;
  while (true) {
    readTrace(top, &traces_count);
    if (get_dii_cmd(traces_count) == 0) {
      eof_trace = true;
    }
    top->clk_i = 0;
    top->eval();
    fflush(stdout);
#if VM_TRACE
    if (vcdfile || fst_fname)
      tfp->dump(static_cast<vluint64_t>(main_time * 2));
#endif
    top->clk_i = 1;
    top->eval();
    fflush(stdout);
#if VM_TRACE
    if (vcdfile || fst_fname)
      tfp->dump(static_cast<vluint64_t>(main_time * 2 + 1));
#endif
    // toggle RTC
    if (main_time % 2 == 0) {
      top->rtc_i ^= 1;
    }
    main_time++;

    // Reset Routine
    if (eof_trace){
      sendReset(traces_count);
      for (int i = 0; i < 10; i++) {
        top->rst_ni = 0;
        top->clk_i = 0;
        top->rtc_i = 0;
        top->eval();
        fflush(stdout);
      #if VM_TRACE
        if (vcdfile || fst_fname)
          tfp->dump(static_cast<vluint64_t>(main_time * 2));
      #endif
        top->clk_i = 1;
        top->eval();
        fflush(stdout);
      #if VM_TRACE
        if (vcdfile || fst_fname)
          tfp->dump(static_cast<vluint64_t>(main_time * 2 + 1));
        #endif
        main_time++;
      }
      top->rst_ni = 1;
      eof_trace = false;
      traces_count++;
      traces_count %= DII_ID_COUNT;
      current_test_dii_start = traces_count;
      // Clear memory
      for (int i = 0; i < (sizeof(MEM0)/sizeof(MEM0[0])); i++) {
          MEM0[i] = 0;
          MEM1[i] = 0;
      }
    }
  }

#if VM_TRACE
  if (tfp)
    tfp->close();
  if (vcdfile)
    fclose(vcdfile);
#endif

  return ret;
}

int test_dii_start() {
  return current_test_dii_start;
}

void readTrace(Variane_testharness_dii *top, unsigned int *rvfi_id) {
  // read rvfi data and add packet to list of packets to send
  // the condition to read data here is that there is an rvfi valid signal
  // this deals with counting instructions that the core has finished executing
  // modify rvfi_id to reflect instructions read
  if (top->rvfi_valid_o_0 || top->rvfi_trap_o_0) {
    rvfi_pkt_t execpacket = readRVFI_0(top);
    print_rvfi_pkt(&execpacket);
    put_rvfi_pkt_wrap(*rvfi_id, &execpacket);
    (*rvfi_id)++;
    (*rvfi_id) %= DII_ID_COUNT;
  }
  if (top->rvfi_valid_o_1 && !top->rvfi_trap_o_0 && !(get_dii_cmd(*rvfi_id) == 0)) { // If there was a trap, the 2nd port should be ignored.
    rvfi_pkt_t execpacket = readRVFI_1(top);
    print_rvfi_pkt(&execpacket);
    put_rvfi_pkt_wrap(*rvfi_id, &execpacket);
    (*rvfi_id)++;
    (*rvfi_id) %= DII_ID_COUNT;
  }
}

void sendReset(unsigned int rvfi_id) {
    rvfi_pkt_t execpacket;
    #define rvfi_field(name, type) execpacket.name = 0;
    for_all_rvfi_fields
    #undef rvfi_field
    execpacket.rvfi_halt = 1;
    put_rvfi_pkt_wrap(rvfi_id, &execpacket);
}

rvfi_pkt_t readRVFI_0(Variane_testharness_dii *top) {
    rvfi_pkt_t execpacket = {
         .rvfi_order = top->rvfi_order_o_0 ,
         .rvfi_pc_rdata = top->rvfi_pc_rdata_o_0 ,
         .rvfi_pc_wdata = top->rvfi_pc_wdata_o_0 ,
         .rvfi_insn = top->rvfi_insn_o_0 ,
         .rvfi_rs1_data = top->rvfi_rs1_rdata_o_0 ,
         .rvfi_rs2_data = top->rvfi_rs2_rdata_o_0 ,
         .rvfi_rd_wdata = top->rvfi_trap_o_0 ? 0 : top->rvfi_rd_wdata_o_0 ,
         .rvfi_mem_addr = top->rvfi_mem_addr_o_0 ,
         .rvfi_mem_rdata = top->rvfi_trap_o_0 ? 0 : top->rvfi_mem_rdata_o_0 ,
         .rvfi_mem_wdata = top->rvfi_trap_o_0 ? 0 : top->rvfi_mem_wdata_o_0 ,
         .rvfi_mem_rmask = top->rvfi_trap_o_0 ? 0 :top->rvfi_mem_rmask_o_0 ,
         .rvfi_mem_wmask = top->rvfi_trap_o_0 ? 0 : top->rvfi_mem_wmask_o_0 ,
         .rvfi_rs1_addr = top->rvfi_trap_o_0 ? 0 : top->rvfi_rs1_addr_o_0 ,
         .rvfi_rs2_addr = top->rvfi_rs2_addr_o_0 ,
         .rvfi_rd_addr = top->rvfi_trap_o_0 ? 0 : top->rvfi_rd_addr_o_0 ,
         .rvfi_trap = top->rvfi_trap_o_0 ,
         .rvfi_halt = 0 ,
         .rvfi_intr = top->rvfi_intr_o_0
     };
    return execpacket;
}

rvfi_pkt_t readRVFI_1(Variane_testharness_dii *top) {
    rvfi_pkt_t execpacket = {
         .rvfi_order = top->rvfi_order_o_1 ,
         .rvfi_pc_rdata = top->rvfi_pc_rdata_o_1 ,
         .rvfi_pc_wdata = top->rvfi_pc_wdata_o_1 ,
         .rvfi_insn = top->rvfi_insn_o_1 ,
         .rvfi_rs1_data = top->rvfi_rs1_rdata_o_1 ,
         .rvfi_rs2_data = top->rvfi_rs2_rdata_o_1 ,
         .rvfi_rd_wdata = top->rvfi_trap_o_1 ? 0 : top->rvfi_rd_wdata_o_1 ,
         .rvfi_mem_addr = top->rvfi_mem_addr_o_1 ,
         .rvfi_mem_rdata = top->rvfi_trap_o_1 ? 0 : top->rvfi_mem_rdata_o_1 ,
         .rvfi_mem_wdata = top->rvfi_trap_o_1 ? 0 : top->rvfi_mem_wdata_o_1 ,
         .rvfi_mem_rmask = top->rvfi_trap_o_1 ? 0 :top->rvfi_mem_rmask_o_1 ,
         .rvfi_mem_wmask = top->rvfi_trap_o_1 ? 0 : top->rvfi_mem_wmask_o_1 ,
         .rvfi_rs1_addr = top->rvfi_trap_o_1 ? 0 : top->rvfi_rs1_addr_o_1 ,
         .rvfi_rs2_addr = top->rvfi_rs2_addr_o_1 ,
         .rvfi_rd_addr = top->rvfi_trap_o_1 ? 0 : top->rvfi_rd_addr_o_1 ,
         .rvfi_trap = top->rvfi_trap_o_1 ,
         .rvfi_halt = 0 ,
         .rvfi_intr = top->rvfi_intr_o_1
     };
    return execpacket;
}
