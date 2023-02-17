#include "libtest.h"

#include "reorder.h"
#include "ring.h"

#include <string.h>
#include <assert.h>
#include <stdio.h>

void permute__create_sorted_array__unsorted_array_and_sorted_from_reordering() {
	uint64_t arr[]      = { 3, 4, 2, 1, 6, 5 };
	uint64_t from[]     = { 3, 2, 0, 1, 5, 4 };
	uint64_t scratch;
	permuteFrom(from, arr, sizeof(uint64_t), 6, &scratch);

	uint64_t expected[] = { 1, 2, 3, 4, 5, 6 };
	assertEqArray(arr, expected, 6);
}

void to__convert_from_index_into_to_index__simple_index() {
	// 3 4 2 1 6 5
	uint64_t from[]     = { 3, 2, 0, 1, 5, 4 };
	uint64_t to[6];
	convertFromIntoTo(from, to, 6, NULL, 0);

	uint64_t expected[] = { 2, 3, 1, 0, 5, 4 };
	assertEqArray(to, expected, 6);
}

void to__map_two_spots_to_same_destination__dupes_were_detected() {
	// 2 4 2 1 5 4
	uint64_t from[]     = { 3, 2, 0, 1, 5, 4 };
	uint64_t to[6];
	uint64_t dupes[] = { 2 };
	convertFromIntoTo(from, to, 6, dupes, 1);

	uint64_t expected[] = { 1, 2, 1, 0, 4, 3 };
	assertEqArray(to, expected, 6);
}

void rings__find_ring__ring_is_single_way() {
	struct node nodesData[] = {
		{0, 0},
		{0, 100},
		{100, 100},
	};
	struct nodes nodes = {
		.nodes =  nodesData,
		.cnt = sizeof(nodesData)/sizeof(struct node),
	};
	uint64_t firstNodes[] = { 0, };
	uint64_t wayNodes[] = { 0, 1, 2, 0 };
	struct ways ways = {
		.firstNode = firstNodes,
		.cnt = sizeof(firstNodes)/sizeof(uint64_t),
		.nodes = wayNodes,
		.nodesCnt = sizeof(wayNodes)/sizeof(uint64_t),
	};

	struct ring ring = {
		.links = malloc(sizeof(struct link) * ways.cnt),
		.firstLink = malloc(sizeof(uint64_t) * ways.cnt),
		.cnt = ways.cnt,
	};
	assert(ring.links != NULL);
	assert(ring.firstLink != NULL);

	int rc = rings_find(nodes, ways, &ring);

	assertEq(rc, 0);
	assertEq(ring.cnt, 1);
	{
		uint64_t expected[] = {0};
		assertEqArray(ring.firstLink, expected, sizeof(uint64_t) * 1);
	}
	assertEq(ring.links[0].way, 0);
	assertEq(ring.links[0].direction, 1);
}

void rings__find_clockwise_ring__ring_is_single_way_clockwise() {
	struct node nodesData[] = {
		{0, 0},
		{100, 100},
		{0, 100},
	};
	struct nodes nodes = {
		.nodes =  nodesData,
		.cnt = sizeof(nodesData)/sizeof(struct node),
	};
	uint64_t firstNodes[] = { 0, };
	uint64_t wayNodes[] = { 0, 1, 2, 0 };
	struct ways ways = {
		.firstNode = firstNodes,
		.cnt = sizeof(firstNodes)/sizeof(uint64_t),
		.nodes = wayNodes,
		.nodesCnt = sizeof(wayNodes)/sizeof(uint64_t),
	};

	struct ring ring = {
		.links = malloc(sizeof(struct link) * ways.cnt),
		.firstLink = malloc(sizeof(uint64_t) * ways.cnt),
		.cnt = ways.cnt,
	};
	assert(ring.links != NULL);
	assert(ring.firstLink != NULL);

	int rc = rings_find(nodes, ways, &ring);

	assertEq(rc, 0);
	assertEq(ring.cnt, 1);
	{
		uint64_t expected[] = {0};
		assertEqArray(ring.firstLink, expected, sizeof(uint64_t) * 1);
	}
	assertEq(ring.links[0].way, 0);
	assertEq(ring.links[0].direction, -1);
}

void rings__find_ring__ring_is_multiple_ways() {
	struct node nodesData[] = {
		{0, 0},
		{0, 100},
		{100, 100},
		{100, 0},
	};
	struct nodes nodes = {
		.nodes =  nodesData,
		.cnt = sizeof(nodesData)/sizeof(struct node),
	};
	uint64_t firstNodes[] = { 0, 3, };
	uint64_t wayNodes[] = { 0, 3, 2, 0, 1, 2, };
	struct ways ways = {
		.firstNode = firstNodes,
		.cnt = sizeof(firstNodes)/sizeof(uint64_t),
		.nodes = wayNodes,
		.nodesCnt = sizeof(wayNodes)/sizeof(uint64_t),
	};

	struct ring ring = {
		.links = malloc(sizeof(struct link) * ways.cnt),
		.firstLink = malloc(sizeof(uint64_t) * ways.cnt),
		.cnt = ways.cnt,
	};
	assert(ring.links != NULL);
	assert(ring.firstLink != NULL);

	int rc = rings_find(nodes, ways, &ring);

	assertEq(rc, 0);
	assertEq(ring.cnt, 1);
	{
		uint64_t expected[] = {0};
		assertEqArray(ring.firstLink, expected, sizeof(uint64_t) * 1);
	}
	assertEq(ring.links[0].way, 1);
	assertEq(ring.links[0].direction, 1);
	assertEq(ring.links[1].way, 0);
	assertEq(ring.links[1].direction, -1);
}

void rings__find_two_disjoint_rings__one_way_is_closed() {
	struct node nodesData[] = {
		{0, 0},
		{0, 100},
		{100, 100},
		{100, 0},
		{200, 100},
		{200, 0},
	};
	struct nodes nodes = {
		.nodes =  nodesData,
		.cnt = sizeof(nodesData)/sizeof(struct node),
	};
	uint64_t firstNodes[] = { 0, 4, 6 };
	uint64_t wayNodes[] = { 0, 1, 2, 0, 3, 4, 4, 5, 3 };
	struct ways ways = {
		.firstNode = firstNodes,
		.cnt = sizeof(firstNodes)/sizeof(uint64_t),
		.nodes = wayNodes,
		.nodesCnt = sizeof(wayNodes)/sizeof(uint64_t),
	};

	struct ring ring = {
		.links = malloc(sizeof(struct link) * ways.cnt),
		.firstLink = malloc(sizeof(uint64_t) * ways.cnt),
		.cnt = ways.cnt,
	};
	assert(ring.links != NULL);
	assert(ring.firstLink != NULL);

	int rc = rings_find(nodes, ways, &ring);

	assertEq(rc, 0);
	assertEq(ring.cnt, 2);
	{
		uint64_t expected[] = {0, 1};
		assertEqArray(ring.firstLink, expected, sizeof(uint64_t) * 2);
	}
	assertEq(ring.links[0].way, 0);
	assertEq(ring.links[0].direction, 1);
	assertEq(ring.links[1].way, 1);
	assertEq(ring.links[1].direction, 1);
	assertEq(ring.links[2].way, 2);
	assertEq(ring.links[2].direction, 1);
}

int main(int argc, char** argv) {
	test_select(argc, argv);

	TEST(permute__create_sorted_array__unsorted_array_and_sorted_from_reordering);

	TEST(to__convert_from_index_into_to_index__simple_index);
	TEST(to__map_two_spots_to_same_destination__dupes_were_detected);

	TEST(rings__find_ring__ring_is_single_way);
	TEST(rings__find_clockwise_ring__ring_is_single_way_clockwise);
	TEST(rings__find_ring__ring_is_multiple_ways);
	TEST(rings__find_two_disjoint_rings__one_way_is_closed);
	return test_end();
}
