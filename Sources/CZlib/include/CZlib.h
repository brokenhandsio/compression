#ifndef CZLIB_H
#define CZLIB_H

#include "zlib.h"
#include <lifetimebound.h>

#if defined(_WIN32)
typedef unsigned char      uint8_t;
typedef uint8_t            u_int8_t;
typedef unsigned short     uint16_t;
typedef uint16_t           u_int16_t;
typedef unsigned           uint32_t;
typedef uint32_t           u_int32_t;
typedef unsigned long long uint64_t;
typedef uint64_t           u_int64_t;
#define snprintf _snprintf
#else
#include <stdint.h>
#endif

static inline int CZlib_deflateInit2(z_streamp strm, int level, int method,
                                     int windowBits, int memLevel,
                                     int strategy) {
  return deflateInit2(strm, level, method, windowBits, memLevel, strategy);
}

static inline int CZlib_inflateInit2(z_streamp strm, int windowBits) {
  return inflateInit2_(strm, windowBits, ZLIB_VERSION, (int)sizeof(z_stream));
}

static inline Bytef *CZlib_voidPtr_to_BytefPtr(const uint8_t *__counted_by(len)
                                                   in         __noescape,
                                               int            len) {
  return (Bytef *)in;
}

static inline Bytef *CZlib_voidPtr_to_BytefPtr_mut(uint8_t *__counted_by(len)
                                                       in   __noescape,
                                                   int      len) {
  return (Bytef *)in;
}

static inline int CZlib_inflateInitDiag(z_streamp strm, int windowBits,
                                        int *outVersionError,
                                        int *outStreamError) {
  // Call inflateInit2_ directly so we can observe which error path fires
  *outVersionError = 0;
  *outStreamError = 0;
  int rc = inflateInit2_(strm, windowBits, ZLIB_VERSION, (int)sizeof(z_stream));
  if (rc == Z_VERSION_ERROR)
    *outVersionError = 1;
  if (rc == Z_STREAM_ERROR)
    *outStreamError = 1;
  return rc;
}

#endif /* CZLIB_H */
