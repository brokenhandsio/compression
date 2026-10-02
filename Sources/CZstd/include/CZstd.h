#ifndef CZSTD_UMBRELLA_H
#define CZSTD_UMBRELLA_H

#include "../lib/zstd.h"
#include "../lib/zstd_errors.h"

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
#else
#define __counted_by(N)
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

#include <stddef.h>
#include <stdint.h>

/// Result of a streaming operation.
///
/// Returned by value so that no buffer pointers cross the Swift boundary.
/// - `status`: zstd's return code. A hint of how many bytes remain to be
///   flushed; `0` means the requested operation completed. Test for failure
///   with `ZSTD_isError`, and translate with `ZSTD_getErrorCode`.
/// - `consumed`: bytes read from `src`.
/// - `produced`: bytes written to `dst`.
typedef struct {
  size_t status;
  size_t consumed;
  size_t produced;
} CZstd_StreamResult;

/// `ZSTD_compress`, taking spans. Only honours `compressionLevel`; use
/// `CZstd_compress2` to apply sticky parameters set on a `ZSTD_CCtx`.
static inline size_t
CZstd_compress(uint8_t *__counted_by(dstCapacity) dst __noescape, size_t dstCapacity,
               const uint8_t *__counted_by(srcSize) src __noescape, size_t srcSize,
               int compressionLevel) {
  return ZSTD_compress((void *)dst, dstCapacity, (const void *)src, srcSize,
                       compressionLevel);
}

/// `ZSTD_compress2`, taking spans. Applies the sticky parameters previously
/// set on `cctx` via `ZSTD_CCtx_setParameter`.
static inline size_t
CZstd_compress2(ZSTD_CCtx *cctx,
                uint8_t *__counted_by(dstCapacity) dst __noescape, size_t dstCapacity,
                const uint8_t *__counted_by(srcSize) src __noescape, size_t srcSize) {
  return ZSTD_compress2(cctx, (void *)dst, dstCapacity, (const void *)src, srcSize);
}

/// `ZSTD_decompressDCtx`, taking spans.
static inline size_t
CZstd_decompressDCtx(ZSTD_DCtx *dctx,
                     uint8_t *__counted_by(dstCapacity) dst __noescape, size_t dstCapacity,
                     const uint8_t *__counted_by(srcSize) src __noescape, size_t srcSize) {
  return ZSTD_decompressDCtx(dctx, (void *)dst, dstCapacity, (const void *)src, srcSize);
}

/// `ZSTD_getFrameContentSize`, taking a span.
///
/// Returns `ZSTD_CONTENTSIZE_UNKNOWN` when the frame header omits the size,
/// or `ZSTD_CONTENTSIZE_ERROR` when `src` is not a valid frame header.
static inline unsigned long long
CZstd_getFrameContentSize(const uint8_t *__counted_by(srcSize) src __noescape, size_t srcSize) {
  return ZSTD_getFrameContentSize((const void *)src, srcSize);
}

/// `ZSTD_compressStream2`, taking spans.
///
/// Both buffers are consumed from offset zero; slice the spans on the Swift
/// side to advance. Empty spans are valid — passing an empty `src` with
/// `ZSTD_e_flush` or `ZSTD_e_end` is the normal way to drain internal buffers.
static inline CZstd_StreamResult
CZstd_compressStream2(ZSTD_CCtx *cctx,
                      uint8_t *dst, size_t dstCapacity,
                      const uint8_t *__counted_by(srcSize) src __noescape, size_t srcSize,
                      ZSTD_EndDirective endOp) {
  ZSTD_outBuffer out = { (void *)dst, dstCapacity, 0 };
  ZSTD_inBuffer in = { (const void *)src, srcSize, 0 };
  size_t const status = ZSTD_compressStream2(cctx, &out, &in, endOp);
  CZstd_StreamResult result = { status, in.pos, out.pos };
  return result;
}

/// `ZSTD_decompressStream`, taking spans.
///
/// A `status` of `0` means a frame boundary was reached. Any other non-error
/// value is a hint at the number of bytes the next call would like to read.
static inline CZstd_StreamResult
CZstd_decompressStream(ZSTD_DCtx *dctx,
                       uint8_t *dst, size_t dstCapacity,
                       const uint8_t *__counted_by(srcSize) src __noescape, size_t srcSize) {
  ZSTD_outBuffer out = { (void *)dst, dstCapacity, 0 };
  ZSTD_inBuffer in = { (const void *)src, srcSize, 0 };
  size_t const status = ZSTD_decompressStream(dctx, &out, &in);
  CZstd_StreamResult result = { status, in.pos, out.pos };
  return result;
}

#endif /* CZSTD_UMBRELLA_H */
