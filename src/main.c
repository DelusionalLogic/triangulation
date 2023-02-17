#define _GNU_SOURCE
#include <arpa/inet.h>
#include <sys/mman.h>
#include <assert.h>
#include <float.h>
#include <sys/stat.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdint.h>
#include <limits.h>

#include <libdeflate.h>

#include "vector.h"
#include "reorder.h"

void eprintf(const char *format, ...) {
	va_list list;
	va_start(list, format);
	vfprintf(stderr, format, list);
	va_end(list);
}

struct pbfPtr {
	uint64_t blockid;
	size_t offset;
	int num;
};

struct mappedIndex {
	int fd;
	void * loc;
};

int mkIndexFile(const char *filename, uint64_t elemSize, uint64_t elemCnt, struct mappedIndex *index) {
	size_t sze = elemCnt * elemSize;
	int mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
	index->fd = open(filename, O_RDWR | O_CREAT | O_TRUNC, mode);
	if (index->fd == -1)
		return -1;
	ftruncate(index->fd, sze);

	index->loc = mmap(NULL, sze, PROT_READ | PROT_WRITE, MAP_SHARED, index->fd, 0);
	if(index->loc == MAP_FAILED) {
		return -1;
	}

	return 0;
}

int openIndexFile(const char *filename, size_t *indexSze, void **indexLoc) {
	int mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
	int file = open(filename, O_RDONLY, mode);
	if (file == -1)
		return -1;

	struct stat st;
	if(fstat(file, &st) != 0) {
		close(file);
		return -1;
	}
	*indexSze = st.st_size;

	*indexLoc = mmap(NULL, *indexSze, PROT_READ, MAP_SHARED, file, 0);
	if(*indexLoc == MAP_FAILED) {
		return -1;
	}

	return 0;
}

struct pbfcursor {
	void* cursor;
#ifndef NDEBUG
	void* end;
#endif
};

uint32_t readInt32(struct pbfcursor *data) {
	assert(data->cursor + 4 <= data->end);

	int32_t value = 0;
	value |= *(uint8_t*)(data->cursor+0) >> 24;
	value |= *(uint8_t*)(data->cursor+1) >> 16;
	value |= *(uint8_t*)(data->cursor+2) >>  8;
	value |= *(uint8_t*)(data->cursor+3) >>  0;

	data->cursor += 4;
	return value;
}

uint64_t readVarInt(struct pbfcursor* data) {
	uint64_t value = 0;

	uint8_t byte;
	uint8_t i = 0;
	do {
		assert(data->cursor + 1 <= data->end);

		byte = *(uint8_t*)data->cursor;

		value |= (uint64_t)(byte & 0x7F) << i;

		data->cursor++;
		i += 7;
	} while(byte & 0x80);

	return value;
}

int64_t readVarZig(struct pbfcursor* data) {
	uint64_t value = readVarInt(data);
	value = (value >> 1) ^ -(value & 1);
	return value;
}

struct sizestr {
	char* str;
	uint64_t len;
};

struct sizestr readString(struct pbfcursor* data) {
	uint64_t len = readVarInt(data);
	assert(data->cursor + len <= data->end);
	char* str = data->cursor;
	data->cursor += len;

	return (struct sizestr){
		.str = str,
		.len = len,
	};
}

void skip(struct pbfcursor *data, uint64_t type) {
	switch(type) {
		case 0:
			readVarInt(data); //Discard it
			break;
		case 1:
			assert(data->cursor + 8 <= data->end);
			data->cursor += 8;
			break;
		case 2: {
			uint64_t len = readVarInt(data);
			assert(data->cursor + len <= data->end);
			data->cursor += len;
			break;
		}
		case 3: case 4:
			abort();
			break;
		case 5:
			assert(data->cursor + 4 <= data->end);
			data->cursor += 4;
			break;
		default:
			abort();
	}
}

#define KEY_PART(x) (x >> 3)
#define TYPE_PART(x) (x & 3)

enum blockType {
	BLOCK_HEADER,
	BLOCK_DATA,
};
enum blockType readBlockType(char* str, size_t strlen) {
	if(strlen == 7 && memcmp(str, "OSMData", 7) == 0) {
		return BLOCK_DATA;
	} else if(strlen == 9 && memcmp(str, "OSMHeader", 9) == 0)  {
		return BLOCK_HEADER;
	}
	abort();
}

struct blobEntry {
	enum blockType type;
	size_t offset;
	size_t size;
};

void buildIndex(FILE *pbf, Vector *index) {
	while(true) {
		size_t r;
		uint32_t headerSize;
		r = fread(&headerSize, 1, 4, pbf);
		if(r < 4) {
			if(feof(pbf)) {
				return;
			} else {
				abort();
			}
		}
		assert(r == 4);
		headerSize = ntohl(headerSize);

		void *buf = malloc(headerSize);
		if(buf == NULL) {
			abort();
		}

		r = fread(buf, 1, headerSize, pbf);
		if(r != headerSize) {
			abort();
		}

		struct pbfcursor headData = {
			.cursor = buf,
			.end = buf + headerSize,
		};

		struct blobEntry entry;
		while(headData.cursor < buf + headerSize){
			uint64_t key = readVarInt(&headData);
			switch(KEY_PART(key)) {
				case 1: {
					struct sizestr str = readString(&headData);
					entry.type = readBlockType(str.str, str.len);
					break;
				}
				case 3:
					entry.size = readVarInt(&headData);
					break;
				default:
					skip(&headData, TYPE_PART(key));
					break;
			}
		}

		entry.offset = ftell(pbf);
		vector_putBack(index, &entry);
		fseek(pbf, entry.size, SEEK_CUR);
	}
}

struct slice {
	void* root;
	void* data;
	size_t size;
};
#define DEFAULT_DECOMPRESS_BUFFER_SIZE (16*1024*1024)

struct slice extractblob(FILE *pbf, struct libdeflate_decompressor* decompressor, size_t offset, size_t size, size_t dsize) {
	dsize = dsize == 0 ? DEFAULT_DECOMPRESS_BUFFER_SIZE : dsize;
	void *buf = malloc(size);
	if(buf == NULL) {
		abort();
	}

	fseek(pbf, offset, SEEK_SET);

	size_t r = fread(buf, 1, size, pbf);
	if(r != size) {
		abort();
	}

	struct pbfcursor data = {
		.cursor = buf,
		.end = buf + size,
	};

	while(data.cursor < buf + size){
		uint64_t key = readVarInt(&data);
		switch(KEY_PART(key)) {
			case 1: {
				// Raw
				struct sizestr str = readString(&data);
				return (struct slice){
					.root = buf,
					.data = str.str,
					.size = str.len,
				};
				break;
			}
			case 3: {
				// zlib_data
				struct sizestr str = readString(&data);
				void* decompbuf = malloc(dsize);
				if(decompbuf == NULL) abort();
				size_t decompsize;
				int rc = libdeflate_zlib_decompress(decompressor, str.str, str.len, decompbuf, dsize, &decompsize);
				if(rc == 0) {
					free(buf);
					return (struct slice){
						.root = decompbuf,
						.data = decompbuf,
						.size = decompsize,
					};
				}
				break;
			}
			default:
				skip(&data, TYPE_PART(key));
				break;
		}
	}

	abort();
}

int indexcmp(const uint64_t* a, const uint64_t* b, const uint64_t* userdata) {
	if (userdata[*a] < userdata[*b]) {
		return -1;
	} else if(userdata[*a] > userdata[*b]) {
		return 1;
	} else {
		return 0;
	}
}

struct ptrCmpData {
	uint64_t *pos;
	struct pbfPtr *ptrs;
};

int ptrcmp(const uint64_t* ai, const uint64_t* bi, const struct ptrCmpData *userdata) {
	struct pbfPtr *a = &userdata->ptrs[userdata->pos[*ai]];
	struct pbfPtr *b = &userdata->ptrs[userdata->pos[*bi]];

	if(a->blockid < b->blockid) {
		return -1;
	} else if(a->blockid > b->blockid) {
		return 1;
	}

	if(a->offset < b->offset) {
		return -1;
	} else if(a->offset > b->offset) {
		return 1;
	}

	if(a->num < b->num) {
		return -1;
	} else if(a->num > b->num) {
		return 1;
	}

	return 0;
}

struct blockData {
	off_t block;
	size_t blockSize;

	size_t blockSizeD;

	int32_t granularity;
	int64_t latOff;
	int64_t lonOff;
};

void build() {
	uint64_t blocksCnt = 1024 * 1024;
	struct mappedIndex blockDatas;
	int err = mkIndexFile("blocks", sizeof(struct blockData), blocksCnt, &blockDatas);
	if(err != 0) {
		printf("Fatal: Could not create block file\n");
		abort();
	}
	struct blockData *blockData = blockDatas.loc;

	uint64_t elemCnt = 128 * 1024 * 1024;
	struct mappedIndex inodeIds;
	err = mkIndexFile("node.id", sizeof(uint64_t), elemCnt, &inodeIds);
	if(err != 0) {
		printf("Fatal: Could not create index file\n");
		abort();
	}
	uint64_t *nodeIds = inodeIds.loc;

	struct mappedIndex inodePtrs;
	err = mkIndexFile("node.ptr", sizeof(struct pbfPtr), elemCnt, &inodePtrs);
	if(err != 0) {
		printf("Fatal: Could not create index file\n");
		abort();
	}
	struct pbfPtr *nodePtrs = inodePtrs.loc;

	struct mappedIndex iwayIds;
	err = mkIndexFile("way.id", sizeof(uint64_t), elemCnt, &iwayIds);
	if(err != 0) {
		printf("Fatal: Could not create index file\n");
		abort();
	}
	uint64_t *wayIds = iwayIds.loc;

	struct mappedIndex iwayPtrs;
	err = mkIndexFile("way.ptr", sizeof(struct pbfPtr), elemCnt, &iwayPtrs);
	if(err != 0) {
		printf("Fatal: Could not create index file\n");
		abort();
	}
	struct pbfPtr *wayPtrs = iwayPtrs.loc;

	struct mappedIndex irelIds;
	err = mkIndexFile("rel.id", sizeof(uint64_t), elemCnt, &irelIds);
	if(err != 0) {
		printf("Fatal: Could not create index file\n");
		abort();
	}
	uint64_t *relIds = irelIds.loc;

	struct mappedIndex irelPtrs;
	err = mkIndexFile("rel.ptr", sizeof(struct pbfPtr), elemCnt, &irelPtrs);
	if(err != 0) {
		printf("Fatal: Could not create index file\n");
		abort();
	}
	struct pbfPtr *relPtrs = irelPtrs.loc;

	uint64_t entryb = 0;
	uint64_t entryi = 0;
	uint64_t entryw = 0;
	uint64_t entryr = 0;

	FILE *pbf = fopen("denmark-latest.osm.pbf", "rb");
	Vector index;
	vector_init(&index, sizeof(struct blobEntry), 8);
	buildIndex(pbf, &index);

	struct libdeflate_decompressor* decompressor;
	decompressor = libdeflate_alloc_decompressor();

	{
		size_t id;
		struct blobEntry *it = vector_getFirst(&index, &id);
		do {
			if(it->type == BLOCK_HEADER) {
				struct slice blob = extractblob(pbf, decompressor, it->offset, it->size, 0);
				struct pbfcursor data = {
					.cursor = blob.data,
					.end = blob.data + blob.size,
				};
				while(data.cursor < blob.data + blob.size){
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
						case 4: {
							struct sizestr str = readString(&data);
							eprintf("sValue is %.*s\n", (int)str.len, str.str);
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
				free(blob.root);
			} else if(it->type == BLOCK_DATA) {
				struct slice blob = extractblob(pbf, decompressor, it->offset, it->size, 0);
				struct pbfcursor data = {
					.cursor = blob.data,
					.end = blob.data + blob.size,
				};

				if(entryb >= blocksCnt) {
					printf("Out of block space\n");
					abort();
				}

				blockData[entryb].block = it->offset;
				blockData[entryb].blockSize = it->size;
				blockData[entryb].blockSizeD = blob.size;

				blockData[entryb].granularity = 100;
				blockData[entryb].latOff = 0;
				blockData[entryb].lonOff = 0;

				while(data.cursor < blob.data + blob.size) {
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
						case 17: {
							// granularity
							blockData[entryb].granularity = readVarInt(&data);
							eprintf("delta %d\n", blockData[entryb].granularity);
							break;
						}
						case 19: {
							// lat_offset
							blockData[entryb].latOff = readVarInt(&data);
							eprintf("latOff %ld\n", blockData[entryb].latOff);
							break;
						}
						case 20: {
							// lon_offset
							blockData[entryb].lonOff = readVarInt(&data);
							eprintf("lonOff %ld\n", blockData[entryb].lonOff);
							break;
						}
						case 2: {
							// primitivegroup
							uint64_t data_len = readVarInt(&data);
							void* data_end = data.cursor + data_len;
							while(data.cursor < data_end) {
								uint64_t key = readVarInt(&data);
								switch(KEY_PART(key)) {
									case 1: {
										// nodes
										// Skip the whole primitivegroup
										// @INCOMPLETE: We probably need to handle these as well
										data.cursor = data_end;
										break;
									}
									case 2: {
										// dense
										uint64_t nodeIndex = 0;
										void* denseStart = data.cursor;

										uint64_t data_len = readVarInt(&data);
										void* data_end = data.cursor + data_len;
										while(data.cursor < data_end) {
											uint64_t key = readVarInt(&data);
											switch(KEY_PART(key)) {
												case 1: {
													// id
													uint64_t data_len = readVarInt(&data);
													void* data_end = data.cursor + data_len;
													uint64_t last = 0;
													while(data.cursor < data_end) {
														int64_t value = readVarZig(&data);
														last += value;
														if(entryi >= elemCnt) {
															printf("Out of index space\n");
															abort();
														}
														nodeIds[entryi] = last;
														nodePtrs[entryi].blockid = entryb;
														nodePtrs[entryi].offset = denseStart - blob.data;
														nodePtrs[entryi].num = nodeIndex;
														nodeIndex++;
														entryi++;
													}
													break;
												}
												default:
													skip(&data, TYPE_PART(key));
													break;
											}
										}
										assert(data.cursor == data_end);
										break;
									}
									case 3: {
										// ways

										if(entryw >= elemCnt) {
											printf("Out of index space\n");
											abort();
										}
										wayPtrs[entryw].blockid = entryb;
										wayPtrs[entryw].offset = data.cursor - blob.data;
										wayPtrs[entryw].num = 0;

										uint64_t data_len = readVarInt(&data);
										void* data_end = data.cursor + data_len;
										while(data.cursor < data_end) {
											uint64_t key = readVarInt(&data);
											switch(KEY_PART(key)) {
												case 1: {
													// id
													wayIds[entryw] = readVarInt(&data);
													break;
												}
												default:
													skip(&data, TYPE_PART(key));
													break;
											}
										}
										assert(data.cursor == data_end);
										entryw++;
										break;
									}
									case 4: {
										// relations

										if(entryr >= elemCnt) {
											printf("Out of index space\n");
											abort();
										}
										relPtrs[entryr].blockid = entryb;
										relPtrs[entryr].offset = data.cursor - blob.data;
										relPtrs[entryr].num = 0;

										uint64_t data_len = readVarInt(&data);
										void* data_end = data.cursor + data_len;
										while(data.cursor < data_end) {
											uint64_t key = readVarInt(&data);
											switch(KEY_PART(key)) {
												case 1: {
													// id
													relIds[entryr] = readVarInt(&data);
													break;
												}
												default:
													skip(&data, TYPE_PART(key));
													break;
											}
										}
										assert(data.cursor == data_end);
										entryr++;
										break;
									}
									default:
										skip(&data, TYPE_PART(key));
										break;
								}
							}
							assert(data.cursor == data_end);
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
				free(blob.root);
				entryb++;
			}

		}while((it = vector_getNext(&index, &id)) != NULL);

	}

	vector_kill(&index);
	eprintf("Found: %lu blocks %lu nodes %lu ways %lu relations\n", entryb, entryi, entryw, entryr);

	ftruncate(blockDatas.fd, sizeof(struct blockData) * entryb);
	close(blockDatas.fd);

	eprintf("Sorting nodes\n");
	{
		uint64_t *fromIndex = malloc(entryi * sizeof(uint64_t));
		for(size_t i = 0; i < entryi; i++) {
			fromIndex[i] = i;
		}
		qsort_r(fromIndex, entryi, sizeof(uint64_t), (__compar_d_fn_t)indexcmp, nodeIds);
		{
			union {
				uint64_t s1;
				struct pbfPtr s2;
			} scratch;
			permuteFrom(fromIndex, nodeIds,  sizeof(uint64_t),      entryi, &scratch);
			permuteFrom(fromIndex, nodePtrs, sizeof(struct pbfPtr), entryi, &scratch);
		}
		free(fromIndex);
	}

	ftruncate(inodeIds.fd, sizeof(uint64_t) * entryi);
	ftruncate(inodePtrs.fd, sizeof(struct pbfPtr) * entryi);
	close(inodeIds.fd);
	close(inodePtrs.fd);

	eprintf("Sorting ways\n");
	{
		uint64_t *fromIndex = malloc(entryw * sizeof(uint64_t));
		for(size_t i = 0; i < entryw; i++) {
			fromIndex[i] = i;
		}
		qsort_r(fromIndex, entryw, sizeof(uint64_t), (__compar_d_fn_t)indexcmp, wayIds);
		{
			union {
				uint64_t s1;
				struct pbfPtr s2;
			} scratch;
			permuteFrom(fromIndex, wayIds,  sizeof(uint64_t),      entryw, &scratch);
			permuteFrom(fromIndex, wayPtrs, sizeof(struct pbfPtr), entryw, &scratch);
		}
		free(fromIndex);
	}

	ftruncate(iwayIds.fd, sizeof(uint64_t) * entryw);
	ftruncate(iwayPtrs.fd, sizeof(struct pbfPtr) * entryw);
	close(iwayIds.fd);
	close(iwayPtrs.fd);

	eprintf("Sorting relations\n");
	{
		uint64_t *fromIndex = malloc(entryr * sizeof(uint64_t));
		for(size_t i = 0; i < entryr; i++) {
			fromIndex[i] = i;
		}
		qsort_r(fromIndex, entryr, sizeof(uint64_t), (__compar_d_fn_t)indexcmp, relIds);
		{
			union {
				uint64_t s1;
				struct pbfPtr s2;
			} scratch;
			permuteFrom(fromIndex, relIds,  sizeof(uint64_t),      entryr, &scratch);
			permuteFrom(fromIndex, relPtrs, sizeof(struct pbfPtr), entryr, &scratch);
		}
		free(fromIndex);
	}

	ftruncate(irelIds.fd, sizeof(uint64_t) * entryr);
	ftruncate(irelPtrs.fd, sizeof(struct pbfPtr) * entryr);
	close(irelIds.fd);
	close(irelPtrs.fd);
}

size_t binSearch(uint64_t *data, size_t elemSize, size_t elemCnt, uint64_t needle) {
	assert(elemSize == sizeof(uint64_t));

	size_t low = 0;
	size_t high = elemCnt - 1;

	while(low <= high) {
		size_t pivot = (high + low) / 2;
		uint64_t elem = data[pivot];
		if(elem == needle) {
			return pivot;
		} else if(elem > needle) {
			high = pivot - 1;
		} else {
			low = pivot + 1;
		}
	}

	eprintf("BAIL on %lu signed %ld\n", needle, (uint64_t)needle);
	return high + 1;
}

void expandMemids(struct pbfPtr *relPtr, FILE *pbf, uint64_t **memidsPtr, size_t *memidsCnt, struct blockData *blockData) {
	struct libdeflate_decompressor* decompressor;
	decompressor = libdeflate_alloc_decompressor();

	struct blockData block = blockData[relPtr->blockid];
	struct slice blob = extractblob(pbf, decompressor, block.block, block.blockSize, block.blockSizeD);
	assert(relPtr->offset < blob.size);
	struct pbfcursor data = {
		.cursor = blob.data + relPtr->offset,
		.end = blob.data + blob.size,
	};

	size_t memberCnt = 0;

	uint64_t data_len = readVarInt(&data);
	void* data_end = data.cursor + data_len;
	while(data.cursor < data_end) {
		uint64_t key = readVarInt(&data);
		switch(KEY_PART(key)) {
			case 10: {
				// types
				uint64_t data_len = readVarInt(&data);
				void* data_end = data.cursor + data_len;
				while(data.cursor < data_end) {
					readVarInt(&data);
					memberCnt++;
				}
				assert(data.cursor == data_end);
				break;
			}
			default:
				skip(&data, TYPE_PART(key));
				break;
		}
	}
	assert(data.cursor == data_end);
	eprintf("Relation contains %lu members\n", memberCnt);

	// Reset the cursor
	data.cursor = blob.data + relPtr->offset;

	uint8_t *types = malloc(sizeof(bool) * memberCnt);
	size_t waysCnt = 0;
	{
		size_t typesi = 0;

		uint64_t data_len = readVarInt(&data);
		void* data_end = data.cursor + data_len;
		while(data.cursor < data_end) {
			uint64_t key = readVarInt(&data);
			switch(KEY_PART(key)) {
				case 10: {
					// types
					uint64_t data_len = readVarInt(&data);
					void* data_end = data.cursor + data_len;
					while(data.cursor < data_end) {
						types[typesi] = readVarInt(&data);
						// @SPEED Maybe this should be vectorized and a post
						// proc
						waysCnt += types[typesi] == 1 ? 1 : 0;
						typesi++;
					}
					break;
				}
				default:
					skip(&data, TYPE_PART(key));
					break;
			}
		}
	}
	eprintf(" of those %lu are ways\n", waysCnt);

	// Reset the cursor
	data.cursor = blob.data + relPtr->offset;

	uint64_t *memids = malloc(sizeof(uint64_t) * waysCnt);
	{
		size_t writei = 0;
		size_t memi = 0;

		uint64_t data_len = readVarInt(&data);
		void* data_end = data.cursor + data_len;
		while(data.cursor < data_end) {
			uint64_t key = readVarInt(&data);
			switch(KEY_PART(key)) {
				case 1: {
					// id
					uint64_t id = readVarInt(&data);
					/* printf("Relation %lu\n", id); */
					break;
				}
				case 9: {
					// memids
					uint64_t data_len = readVarInt(&data);
					void* data_end = data.cursor + data_len;
					uint64_t last = 0;
					while(data.cursor < data_end) {
						int64_t value = readVarZig(&data);
						last += value;
						if(types[memi] == 1) { // Way
							memids[writei++] = last;
						}
						memi++;
					}
					break;
				}
				default:
					skip(&data, TYPE_PART(key));
					break;
			}
		}
	}

	*memidsCnt = waysCnt;
	*memidsPtr = memids;

	free(types);
	free(blob.data);
	libdeflate_free_decompressor(decompressor);
}

/* void expandRefs(struct pbfPtr *ways, size_t wayCnt, FILE *pbf, uint64_t *(*refs)[], size_t (*refCnt)[]) { */
/* } */

void lookupIds(uint64_t *needles, size_t needleCnt, uint64_t *wayIds, size_t wayCnt, size_t *pos) {
	// @SPEED It seems like it should be possible to do this faster if you somehow
	// compare all the id's at the same time.
	for (size_t i = 0; i < needleCnt; i++) {
		pos[i] = binSearch(wayIds, sizeof(uint64_t), wayCnt, needles[i]);
	}
}

void lookup() {
	size_t indexSze;
	int err;

	struct blockData *blockData;
	err = openIndexFile("blocks", &indexSze, (void**)&blockData);
	if(err != 0) {
		printf("Fatal: Could not open block file\n");
		abort();
	}
	uint32_t blockCnt = indexSze/sizeof(struct blockData);
	assert(blockCnt * sizeof(struct blockData) == indexSze);

	uint64_t *nodeIds;
	err = openIndexFile("node.id", &indexSze, (void**)&nodeIds);
	if(err != 0) {
		printf("Fatal: Could not open index file\n");
		abort();
	}
	uint32_t nodeCnt = indexSze/sizeof(uint64_t);
	assert(nodeCnt * sizeof(uint64_t) == indexSze);

	struct pbfPtr *nodePtrs;
	err = openIndexFile("node.ptr", &indexSze, (void**)&nodePtrs);
	if(err != 0) {
		printf("Fatal: Could not open index file\n");
		abort();
	}
	assert(nodeCnt * sizeof(struct pbfPtr) == indexSze);

	uint64_t *wayIds;
	err = openIndexFile("way.id", &indexSze, (void**)&wayIds);
	if(err != 0) {
		printf("Fatal: Could not open index file\n");
		abort();
	}
	uint32_t wayCnt = indexSze/sizeof(uint64_t);
	assert(wayCnt * sizeof(uint64_t) == indexSze);

	struct pbfPtr *wayPtrs;
	err = openIndexFile("way.ptr", &indexSze, (void**)&wayPtrs);
	if(err != 0) {
		printf("Fatal: Could not open index file\n");
		abort();
	}
	assert(wayCnt * sizeof(struct pbfPtr) == indexSze);

	uint64_t *relIds;
	err = openIndexFile("rel.id", &indexSze, (void**)&relIds);
	if(err != 0) {
		printf("Fatal: Could not open index file\n");
		abort();
	}
	uint32_t relCnt = indexSze/sizeof(uint64_t);
	assert(relCnt * sizeof(uint64_t) == indexSze);

	struct pbfPtr *relPtrs;
	err = openIndexFile("rel.ptr", &indexSze, (void**)&relPtrs);
	if(err != 0) {
		printf("Fatal: Could not open index file\n");
		abort();
	}
	assert(relCnt * sizeof(struct pbfPtr) == indexSze);

	eprintf("Found: %u nodes %u ways %u relations\n", nodeCnt, wayCnt, relCnt);

	uint64_t relid = 8312746;
	size_t item = binSearch(relIds, sizeof(uint64_t), relCnt, relid);
	eprintf("Found: Relation %lu at %lu, val %lu\n", relid, item, relIds[item]);

	FILE *pbf = fopen("denmark-latest.osm.pbf", "rb");
	uint64_t *members;
	size_t memberCnt;
	expandMemids(&relPtrs[item], pbf, &members, &memberCnt, blockData);

	size_t *memberPos = malloc(sizeof(size_t) * memberCnt);
	lookupIds(members, memberCnt, wayIds, wayCnt, memberPos);
	eprintf("member[%lu] = %lu\n", memberPos[398], wayIds[memberPos[398]]);

	// Array of pointers to the array of nodeids. One array per member
	uint64_t **refs = malloc(sizeof(uint64_t) * memberCnt);
	// The number of nodes per member way
	size_t *refCnt = malloc(sizeof(size_t) * memberCnt);
	// Expand the ways to find all the nodes
	{

		struct libdeflate_decompressor* decompressor;
		decompressor = libdeflate_alloc_decompressor();

		// @SPEED For now we just expand each member in whatever order
		// they happen to appear in. To increase efficiency, we could
		// sort them based on the ptr block first (to maybe get some
		// more use out of our decompression)
		for(size_t i = 0; i < memberCnt; i++) {
			struct pbfPtr wayPtr = wayPtrs[memberPos[i]];
			struct blockData block = blockData[wayPtr.blockid];
			struct slice blob = extractblob(pbf, decompressor, block.block, block.blockSize, block.blockSizeD);
			assert(wayPtr.offset < blob.size);

			struct pbfcursor data = {
				.cursor = blob.data + wayPtr.offset,
				.end = blob.data + blob.size,
			};

			// Count the number of refs
			{
				refCnt[i] = 0;

				uint64_t data_len = readVarInt(&data);
				void* data_end = data.cursor + data_len;
				while(data.cursor < data_end) {
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
						case 8: {
							// refs
							uint64_t data_len = readVarInt(&data);
							void* data_end = data.cursor + data_len;
							while(data.cursor < data_end) {
								readVarInt(&data);
								refCnt[i]++;
							}
							assert(data.cursor == data_end);
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
				assert(data.cursor == data_end);
				eprintf("Way contains %lu nodes\n", refCnt[i]);
			}

			// Reset the cursor
			data.cursor = blob.data + wayPtr.offset;

			refs[i] = malloc(sizeof(uint64_t) * refCnt[i]);
			{
				size_t memi = 0;

				uint64_t data_len = readVarInt(&data);
				void* data_end = data.cursor + data_len;
				uint64_t last = 0;
				while(data.cursor < data_end) {
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
						case 8: {
							// refs
							uint64_t data_len = readVarInt(&data);
							void* data_end = data.cursor + data_len;
							while(data.cursor < data_end) {
								int64_t value = readVarZig(&data);
								last += value;
								refs[i][memi++] = last;
							}
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
			}
		}

		libdeflate_free_decompressor(decompressor);

	}
	free(memberPos);

	// Find internal node ids
	size_t totalNodeCnt = 0;
	for(size_t i = 0; i < memberCnt; i++) {
		totalNodeCnt += refCnt[i];
	}

	// Flatten the result into one array
	size_t *nodePos = malloc(sizeof(size_t) * totalNodeCnt);
	size_t *nodePosCursor = nodePos;
	for(size_t i = 0; i < memberCnt; i++) {
		size_t cnt = refCnt[i];
		eprintf("way[%lu] %lu\n", i, members[i]);
		lookupIds(refs[i], refCnt[i], nodeIds, nodeCnt, nodePosCursor);
		nodePosCursor += refCnt[i];
	}

	uint64_t *toIndex;
	{
		eprintf("Sorting the selected nodes\n");
		uint64_t *fromIndex = malloc(sizeof(uint64_t) * totalNodeCnt);
		for(size_t i = 0; i < totalNodeCnt; i++) {
			fromIndex[i] = i;
		}
		qsort_r(fromIndex, totalNodeCnt, sizeof(uint64_t), ptrcmp, &(struct ptrCmpData){
			.pos = nodePos,
			.ptrs = nodePtrs,
		});

		{
			uint64_t s1;
			permuteFrom(fromIndex, nodePos, sizeof(uint64_t), totalNodeCnt, &s1);
		}

		// Remove duplicates
		uint64_t *dupes = NULL;
		size_t skip = 0;
		if(totalNodeCnt > 0) {
			// @MEMORY This is waaaay oversized
			dupes = malloc(sizeof(uint64_t) * totalNodeCnt);
			uint64_t last = nodePos[0];
			for(size_t i = 1; i < totalNodeCnt; i++) {
				if(nodePos[i] != last) {
					nodePos[i - skip] = nodePos[i];
				} else {
					dupes[skip] = i;
					skip++;
				}
				/* eprintf("Compare %lu (block %lu offset %lu) and %lu (block %lu offset %lu)\n", last, nodePtrs[last].blockid, nodePtrs[last].offset, nodePos[i], nodePtrs[nodePos[i]].blockid, nodePtrs[nodePos[i]].offset); */
				last = nodePos[i];
			}
			eprintf("%d duplicates removed\n", skip);
		}

		toIndex = malloc(sizeof(uint64_t) * totalNodeCnt);
		convertFromIntoTo(fromIndex, toIndex, totalNodeCnt, dupes, skip);
		free(fromIndex);
		if(dupes != NULL) free(dupes);
	}

	// Lookup the node attributes that we need
	int64_t *lat = malloc(sizeof(int64_t) * totalNodeCnt);
	int64_t *lon = malloc(sizeof(int64_t) * totalNodeCnt);
	{

		struct libdeflate_decompressor* decompressor;
		decompressor = libdeflate_alloc_decompressor();

		// @SPEED For now we just expand each item in whatever order they
		// happen to appear in. To increase efficiency, we could sort them
		// based on the ptr block first (to maybe get some more use out of our
		// decompression)
		for(size_t i = 0; i < totalNodeCnt; i++) {
			struct pbfPtr nodePtr = nodePtrs[nodePos[i]];
			struct blockData block = blockData[nodePtr.blockid];
			struct slice blob = extractblob(pbf, decompressor, block.block, block.blockSize, block.blockSizeD);

			struct pbfcursor data = {
				.cursor = blob.data + nodePtr.offset,
				.end = blob.data + blob.size,
			};

			{
				uint64_t data_len = readVarInt(&data);
				void* data_end = data.cursor + data_len;
				while(data.cursor < data_end) {
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
						case 1: {
							// id
							uint64_t data_len = readVarInt(&data);
							void* data_end = data.cursor + data_len;
							uint64_t last = 0;
							for(size_t j = 0; j < nodePtr.num; j++) {
								int64_t value = readVarZig(&data);
								last += value;
							}
							int64_t value = readVarZig(&data);
							last += value;
							assert(nodeIds[nodePos[i]] == last);
							data.cursor = data_end;
							break;
						}
						case 8: {
							// lat
							uint64_t data_len = readVarInt(&data);
							void* data_end = data.cursor + data_len;
							int64_t last = 0;
							for(size_t j = 0; j < nodePtr.num; j++) {
								int64_t value = readVarZig(&data);
								last += value;
							}
							int64_t value = readVarZig(&data);
							last += value;
							lat[i] = last;
							data.cursor = data_end;
							break;
						}
						case 9: {
							// lon
							uint64_t data_len = readVarInt(&data);
							void* data_end = data.cursor + data_len;
							int64_t last = 0;
							for(size_t j = 0; j < nodePtr.num; j++) {
								int64_t value = readVarZig(&data);
								last += value;
							}
							int64_t value = readVarZig(&data);
							last += value;
							lon[i] = last;
							data.cursor = data_end;
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
				assert(data.cursor == data_end);
			}
		}

		libdeflate_free_decompressor(decompressor);

	}

	printf("begin nodes\n");
	for(size_t i = 0; i < totalNodeCnt; i++) {
		struct blockData *block = blockData + nodePtrs[nodePos[i]].blockid;

		double latCorrected = .000000001 * (blockData->latOff + (blockData->granularity * lat[i]));
		double lonCorrected = .000000001 * (blockData->lonOff + (blockData->granularity * lon[i]));
		printf("node iid %lu\n", i);
		printf("node id %lu\n", nodeIds[nodePos[i]]);
		printf("node pos %.*f %.*f\n", DBL_DIG, latCorrected, DBL_DIG, lonCorrected);
	}

	printf("begin ways\n");
	{
		uint64_t id = 0;
		for(size_t i = 0; i < memberCnt; i++) {
			printf("way\n");
			for(size_t j = 0; j < refCnt[i]; j++) {
				printf("mem %ld\n", toIndex[id++]);
			}
		}
	}

	printf("begin relations\n");
	printf("relation\n");
	for(size_t i = 0; i < memberCnt; i++) {
		printf("mem %ld\n", i);
	}

	free(lon);
	free(lat);

	for(size_t i = 0; i < memberCnt; i++) {
		free(refs[i]);
	}
	free(refs);
	free(refCnt);
	free(members);
}

int main(int argc, char** argv) {
	if(argc != 2) {
		printf("Wrong number of arguments\n");
		exit(1);
	}

	if(strcmp(argv[1], "build") == 0) {
		build();
	} else if(strcmp(argv[1], "lookup") == 0) {
		lookup();
	}

	return 0;
}
