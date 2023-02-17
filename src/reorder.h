#pragma once

#include <stdint.h>
#include <stddef.h>

struct order {
    uint64_t* elem;
    size_t elemCnt;
};

void permuteFrom(uint64_t* from, void* data, size_t elemSize, size_t elemCnt, void* scratch);
void convertFromIntoTo(uint64_t *from, uint64_t *to, size_t elemCnt, uint64_t *dupes, size_t dupeCnt);
