#include <arpa/inet.h>
#include <assert.h>
#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include <libdeflate.h>

#include "vector.h"

int mkIndexFile() {
	int mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
	int file = open("sparsefile", O_WRONLY | O_CREAT, mode);
	if (file == -1)
		return -1;
	ftruncate(file, 0x100000);
	close(file);

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

		value |= (byte & 0x7F) << i;

		data->cursor++;
		i += 7;
	} while(byte & 0x80);

	return value;
}

int64_t readVarZig(struct pbfcursor* data) {
	uint64_t value = readVarInt(data);
	value = (value >> 1) ^ (((int64_t)value<<63) >> 63);
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

struct slice extractblob(FILE *pbf, struct libdeflate_decompressor* decompressor, struct blobEntry *entry) {
	void *buf = malloc(entry->size);
	if(buf == NULL) {
		abort();
	}

	fseek(pbf, entry->offset, SEEK_SET);

	size_t r = fread(buf, 1, entry->size, pbf);
	if(r != entry->size) {
		abort();
	}

	struct pbfcursor data = {
		.cursor = buf,
		.end = buf + entry->size,
	};

	while(data.cursor < buf + entry->size){
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
				void* decompbuf = malloc(DEFAULT_DECOMPRESS_BUFFER_SIZE);
				if(decompbuf == NULL) abort();
				size_t decompsize;
				int rc = libdeflate_zlib_decompress(decompressor, str.str, str.len, decompbuf, DEFAULT_DECOMPRESS_BUFFER_SIZE, &decompsize);
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

int main(int argc, char** argv) {
	printf("Hello world\n");

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
				struct slice blob = extractblob(pbf, decompressor, it);
				struct pbfcursor data = {
					.cursor = blob.data,
					.end = blob.data + blob.size,
				};
				while(data.cursor < blob.data + blob.size){
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
						case 4: {
							struct sizestr str = readString(&data);
							printf("Value is %.*s\n", (int)str.len, str.str);
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
				free(blob.root);
			} else if(it->type == BLOCK_DATA) {
				struct slice blob = extractblob(pbf, decompressor, it);
				struct pbfcursor data = {
					.cursor = blob.data,
					.end = blob.data + blob.size,
				};
				while(data.cursor < blob.data + blob.size){
					uint64_t key = readVarInt(&data);
					switch(KEY_PART(key)) {
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
										data.cursor = data_end;
										break;
									}
									case 2: {
										// dense
										uint64_t data_len = readVarInt(&data);
										void* data_end = data.cursor + data_len;
										while(data.cursor < data_end) {
											uint64_t key = readVarInt(&data);
											switch(KEY_PART(key)) {
												case 1: {
													// id
														uint64_t data_len = readVarInt(&data);
														void* data_end = data.cursor + data_len;
														while(data.cursor < data_end) {
															int64_t value = readVarZig(&data);
															printf("Value is %ld\n", value);
														}
													break;
												}
												default:
													skip(&data, TYPE_PART(key));
													break;
											}
										}
										break;
									}
									default:
										skip(&data, TYPE_PART(key));
										break;
								}
							}
							break;
						}
						default:
							skip(&data, TYPE_PART(key));
							break;
					}
				}
				free(blob.root);
			}
		}while((it = vector_getNext(&index, &id)) != NULL);

	}

	vector_kill(&index);
	return 0;
}
