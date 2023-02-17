#pragma once

#include <stdint.h>
#include <stdio.h>

struct node {
	float x;
	float y;
};

struct nodes {
	struct node *nodes;
	size_t cnt;
};

struct ways {
	uint64_t* firstNode;
	size_t cnt;

	// Nodes in the ways as a lookup into the nodes->nodes array
	uint64_t* nodes;
	size_t nodesCnt;
};

struct link {
	size_t way;
	// -1 for clockwise, 1 for anticlockwise
	int8_t direction;
};

struct ring {
	struct link *links;
	// The index of the first link in a ring.
	uint64_t *firstLink;
	size_t cnt;
};

int rings_find(struct nodes nodes, struct ways ways, struct ring *ring);
