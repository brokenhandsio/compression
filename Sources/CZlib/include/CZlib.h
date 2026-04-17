#ifndef CZLIB_H
#define CZLIB_H

#include "zlib.h"

#if __has_include(<lifetimebound.h>)
#include <lifetimebound.h>
#endif
#if __has_include(<ptrcheck.h>)
#include <ptrcheck.h>
#endif

#if defined(__has_feature) && __has_feature(bounds_attributes)
#define __has_ptrcheck 1
#else
#define __has_ptrcheck 0
#endif

#if defined(__has_feature) && __has_feature(bounds_safety_attributes)
#define __has_bounds_safety_attributes 1
#else
#define __has_bounds_safety_attributes 0
#endif

#if __has_ptrcheck || __has_bounds_safety_attributes
#define __counted_by(N) __attribute__((__counted_by__(N)))
#endif

#if defined(__cplusplus) && defined(__has_cpp_attribute)
#define __use_cpp_spelling(x) __has_cpp_attribute(x)
#else
#define __use_cpp_spelling(x) 0
#endif

#if __use_cpp_spelling(clang::noescape)
#define __noescape [[clang::noescape]]
#else
#define __noescape __attribute__((noescape))
#endif

#if defined(_WIN32)
#define snprintf _snprintf
#endif

#include <stdint.h>

#if !defined(__APPLE__) && !defined(__FreeBSD__)
typedef uint8_t u_int8_t;
typedef uint16_t u_int16_t;
typedef uint32_t u_int32_t;
typedef uint64_t u_int64_t;
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
                                                   in __noescape,
                                               int len) {
  return (Bytef *)in;
}

static inline Bytef *CZlib_voidPtr_to_BytefPtr_mut(uint8_t *__counted_by(len)
                                                       in __noescape,
                                                   int len) {
  return (Bytef *)in;
}

#endif /* CZLIB_H */
