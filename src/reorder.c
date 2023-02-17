#include "reorder.h"

#include <limits.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#define SIZE_BITS (sizeof(size_t)*CHAR_BIT)
void permuteFrom(uint64_t* from, void* data, size_t elemSize, size_t elemCnt, void* scratch) {
	assert(elemCnt>>(SIZE_BITS-1) == 0);
#ifndef NDEBUG
	// Save the from so that we can check that we don't touch it (only if debug
	// is enabled)
	uint64_t *sourceArray = malloc(sizeof(uint64_t) * elemCnt);
	memcpy(sourceArray, from, sizeof(uint64_t) * elemCnt);
#endif

	// Permute the data according to the indexes in from, in place. If the from
	// array at position 0 contains the value 4, the value at position 4 in the
	// data array must be copied to position 0. What complicates this is that
	// position 0 must first be vacated such that we don't lose the data in
	// there. To accomplish that task we first copy the data at position 0 into
	// a scratch buffer (provided by the user) and then chase the from index
	// around to figure out where that data should go. It turns out (there's
	// probably a proof for this) that if you chase the index around, 0 takes
	// from 4 which takes from 5 which takes from x, you'll eventually land
	// back at something that takes from 0. Once you reach something that takes
	// from 0 you've completed the ring and you can take the 0 value out of the
	// scratch buffer and place it in there. While you walk that ring we can
	// copy the data values over as well to permute that array.
	//
	// It's important to note that all indicies can only be part of 1 ring, but
	// that a single array can contain multiple rings. To keep track of which
	// rings we have processed (since every ring only need to be processed
	// once) we set the top bit of all the from elements we have processed.
	for(size_t i = 0; i < elemCnt; i++) {
		// If the top bit is set we've already touched this
		if(from[i] & 1ULL << (SIZE_BITS-1))
			continue;

		memcpy(scratch, data + i*elemSize, elemSize);

		size_t dest = i;
		while(true) {
			size_t source = from[dest];
			from[dest] = source | (1ULL << (SIZE_BITS-1));

			// When we arrive back at the start of the ring we're done
			if(source == i) break;

			memcpy(data + dest*elemSize, data + source*elemSize, elemSize);
			dest = source;
		}

		memcpy(data + dest*elemSize, scratch, elemSize);
	}

	// Reset the marker bits
	for(size_t i = 0; i < elemCnt; i++) {
		assert((from[i] & (1ULL << (SIZE_BITS-1))) != 0);
		from[i] &= (1ULL << (SIZE_BITS-1)) - 1;
	}

#ifndef NDEBUG
	assert(memcmp(sourceArray, from, sizeof(uint64_t) * elemCnt) == 0);
	free(sourceArray);
#endif
}

void convertFromIntoTo(uint64_t *from, uint64_t *to, size_t elemCnt, uint64_t *dupes, size_t dupeCnt) {
	assert(elemCnt>>(SIZE_BITS-1) == 0);

	size_t begin = 0;
	for(size_t i = 0; i < dupeCnt; i++) {
		for(; begin < dupes[i]; begin++) {
			to[from[begin]] = begin-i;
		}
		to[from[begin]] = to[from[begin-1]];
		begin++;
	}
	for(size_t j = begin; j < elemCnt; j++) {
		to[from[j]] = j-dupeCnt;
	}
}
