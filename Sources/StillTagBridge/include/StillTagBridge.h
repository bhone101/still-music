#ifndef STILL_TAG_BRIDGE_H
#define STILL_TAG_BRIDGE_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
int still_read_property(const char *path, const char *key, char *value, size_t capacity);
int still_read_artwork(const char *path, const char *format, unsigned char *bytes, size_t capacity, size_t *size);
int still_write_property(const char *path, const char *key, const char *value);
int still_write_artwork(const char *path, const char *format, const unsigned char *bytes, size_t size, int png);
// Edits a disposable copy only. NULL lyrics removes all supported lyric tags.
int still_write_lyrics(const char *path, const char *format, const char *lyrics,
                      char *error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
