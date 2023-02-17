#include "ring.h"

#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>

static double pseudoangle(double x, double y) {
	double r = x / (fabs(x) + fabs(y));
	if(y < 0)
		return r - 1.0;
	return 1.0 - r;
}

static size_t endOfWay(struct ways ways, size_t way, int direction) {
	if(direction == 1) {
		return ways.firstNode[way];
	} else {
		if(way+1 >= ways.cnt) {
			return ways.nodesCnt-1;
		} else {
			return ways.firstNode[way+1]-1;
		}
	}
}

int rings_find(struct nodes nodes, struct ways ways, struct ring *ring) {
	uint8_t *usedWays = calloc(ways.cnt, sizeof(uint8_t));
	if(usedWays == NULL) abort();
	size_t remain = ways.cnt;

	size_t maxRings = ring->cnt;
	ring->cnt = 0;
	size_t nextLink = 0;

	// Handle the closed ways (single way forms a cycle)
	for(size_t i = 0; i < ways.cnt; i++) {
		uint64_t firsti = ways.firstNode[i];
		uint64_t lasti = i == ways.cnt-1 ? ways.nodesCnt-1 : ways.firstNode[i+1]-1;

		if(lasti - firsti < 2) continue;

		uint64_t first = ways.nodes[firsti];
		uint64_t last = ways.nodes[lasti];
		if(first == last) {
			assert(nextLink < ways.cnt);
			ring->links[nextLink] = (struct link){
				.way = i,
				.direction = 1 // @INCOMPLETE: We need to calculate the direction here
			};
			usedWays[i] = 1;
			remain--;
			assert(ring->cnt < maxRings);
			ring->firstLink[ring->cnt] = nextLink;
			nextLink++;
			ring->cnt++;
		}
	}

	if(remain == 0) return 0;

	// Rings that require connecting multiple cycles

	// Find the leftmost node
	size_t minI = 0;
	{
		uint64_t minX = -1;
		size_t way = 0;
		for(size_t wi = 0; wi < ways.nodesCnt; wi++) {
			while(way+1 < ways.cnt && ways.firstNode[way+1] <= wi) way++;
			printf("Check %ld of way %ld\n", wi, way);
			if(usedWays[way]) continue;
			printf("No skip\n");

			size_t i = ways.nodes[wi];
			if(minX == -1 || nodes.nodes[i].x < minX) {
				minI = i;
				minX = nodes.nodes[i].x;
			}
		}
	}
	printf("%ld is the leftmost node\n", minI);

	double minangle = DBL_MAX;
	size_t minWay;
	int direction;

	// Find the leftmost way (and direction) in the counterclockwise winding order
	size_t way = 0;
	for(size_t i = 0; i < ways.nodesCnt; i++) {
		if(ways.nodes[i] == minI) {
			printf("%ld == %ld at position %ld\n", minI, ways.nodes[i], i);
			// Skip to the current way
			while(way+1 < ways.cnt && ways.firstNode[way+1] <= i) way++;
			if(ways.firstNode[way] < i) {
				// Check negative direction
				size_t nodei = ways.nodes[i-1];
				struct node* node = &nodes.nodes[nodei];
				float localx = node->x - nodes.nodes[minI].x;
				float localy = node->y - nodes.nodes[minI].y;
				double angle = fmod(0 - pseudoangle(localx, localy), 4);

				if(angle < minangle) {
					printf("New min angle %f\n", angle);
					minangle = angle;
					minWay = way;
					direction = -1;
				}
			}

			if((way+1 < ways.cnt && i < ways.firstNode[way+1]) || i+1 < ways.nodesCnt) {
				// Check positive direction
				size_t nodei = ways.nodes[i+1];
				struct node* node = &nodes.nodes[nodei];
				float localx = node->x - nodes.nodes[minI].x;
				float localy = node->y - nodes.nodes[minI].y; double angle = fmod(0 - pseudoangle(localx, localy), 4);

				if(angle < minangle) {
					printf("New min angle %f\n", angle);
					minangle = angle;
					minWay = way;
					direction = 1;
				}
			}
		}
	}

	{
		assert(nextLink < ways.cnt);
		ring->links[nextLink] = (struct link){
			.way = minWay,
			.direction = direction,
		};
		assert(ring->cnt < maxRings);
		ring->firstLink[ring->cnt] = nextLink;
		nextLink++;
		ring->cnt++;
	}

	// Notice that we reverse the direction since we want the opposite end than the one we are going to walk
	size_t begin;
	{
		size_t nodei = endOfWay(ways, minWay, -direction);;
		begin = ways.nodes[nodei];
	}

	// Follow the way around to build a ring

	while(1) {
		printf("We pick way %lu in direction %d\n", minWay, direction);
		usedWays[minWay] = 1;

		size_t nnode;
		double refAngle;
		{
			size_t endi = endOfWay(ways, minWay, direction);
			nnode = ways.nodes[endi];
			size_t lnode = ways.nodes[endi + direction];

			float localx = nodes.nodes[lnode].x - nodes.nodes[nnode].x;
			float localy = nodes.nodes[lnode].y - nodes.nodes[nnode].y;
			refAngle = fmod(0 - pseudoangle(localx, localy), 4);
		}

		// If we return to the start the ring is complete
		if(nnode == begin) break;

		double minAngle = DBL_MAX;
		size_t nextWay = 0;
		size_t nextDirection = 0;
		printf("Fetch angles for neighbours to %ld\n", nnode);
		for(size_t i = 0; i < ways.cnt; i++) {
			if(usedWays[i]) continue;

			{ // Forwards
				size_t endi = endOfWay(ways, i, 1);
				if(ways.nodes[endi] == nnode) {
					size_t lnode = ways.nodes[endi+1];
					float localx = nodes.nodes[lnode].x - nodes.nodes[nnode].x;
					float localy = nodes.nodes[lnode].y - nodes.nodes[nnode].y;
					double angle = fmod(refAngle - pseudoangle(localx, localy), 4);
					if(angle < minAngle) {
						nextWay = i;
						nextDirection = -1;
					}
				}
			}

			{ // Backwards
				size_t endi = endOfWay(ways, i, -1);
				if(ways.nodes[endi] == nnode) {
					size_t lnode = ways.nodes[endi-1];
					float localx = nodes.nodes[lnode].x - nodes.nodes[nnode].x;
					float localy = nodes.nodes[lnode].y - nodes.nodes[nnode].y;
					double angle = fmod(refAngle - pseudoangle(localx, localy), 4);
					if(angle < minAngle) {
						nextWay = i;
						nextDirection = 1;
					}
				}
			}
		}
		minWay = nextWay;
		direction = nextDirection;

		{
			assert(nextLink < ways.cnt);
			ring->links[nextLink] = (struct link){
				.way = minWay,
				.direction = direction,
			};
			nextLink++;
		}
	}

	return 0;
}
