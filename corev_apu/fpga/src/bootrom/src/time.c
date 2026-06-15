// Copyright OpenHW Group contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "time.h"

#define MILLISECOND_CYCLES (CLOCK_FREQUENCY / 1000)

unsigned long get_cycle_count() {
    unsigned long cycle;
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycle));
    return cycle;
}

void millisleep(unsigned long millis) {
    unsigned long start = get_cycle_count();
    while(get_cycle_count() - start < MILLISECOND_CYCLES * millis);
}
