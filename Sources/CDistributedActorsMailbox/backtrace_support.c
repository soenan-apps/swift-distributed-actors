//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Modified by Soenan for musl platform support.
#include <stdlib.h>
#include <stdio.h>
#if defined(__linux__) && !defined(__GLIBC__)
#include <stdint.h>
#include <unwind.h>
#else
#include <execinfo.h>
#endif

#include "include/backtrace_support.h"

#if defined(__linux__) && !defined(__GLIBC__)
struct sact_backtrace {
    void* addresses[128];
    int count;
};

static _Unwind_Reason_Code sact_capture_frame(struct _Unwind_Context* context, void* argument) {
    struct sact_backtrace* trace = argument;
    uintptr_t address = _Unwind_GetIP(context);
    if (address == 0 || trace->count == 128) {
        return _URC_END_OF_STACK;
    }
    trace->addresses[trace->count++] = (void*)address;
    return _URC_NO_REASON;
}
#endif

void sact_dump_backtrace() {
    char** strs;
    int frames = sact_get_backtrace(&strs);
    for (int i = 0; i < frames; ++i) {
        fprintf(stderr, "%s\n", strs[i]);
    }
    free(strs);
}

int sact_get_backtrace(char*** strs) {
#if !defined(__linux__) || defined(__GLIBC__)
    void* callstack[128];
    int frames = backtrace(callstack, 128);
    *strs = backtrace_symbols(callstack, frames);
    return frames;
#else
    struct sact_backtrace trace;
    trace.count = 0;
    _Unwind_Backtrace(sact_capture_frame, &trace);
    *strs = NULL;
    if (trace.count == 0) {
        return 0;
    }

    const size_t bytesPerFrame = 2 * sizeof(void*) + 5;
    char** symbols = malloc((size_t)trace.count * (sizeof(char*) + bytesPerFrame));
    if (symbols == NULL) {
        return 0;
    }
    char* text = (char*)(symbols + trace.count);
    for (int i = 0; i < trace.count; ++i) {
        symbols[i] = text;
        snprintf(text, bytesPerFrame, "[%p]", trace.addresses[i]);
        text += bytesPerFrame;
    }
    *strs = symbols;
    return trace.count;
#endif
}
