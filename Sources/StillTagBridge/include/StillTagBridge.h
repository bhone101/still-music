#ifndef STILL_TAG_BRIDGE_H
#define STILL_TAG_BRIDGE_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Edits a disposable copy only. NULL lyrics removes all supported lyric tags.
int still_write_lyrics(const char *path, const char *format, const char *lyrics,
                      char *error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
