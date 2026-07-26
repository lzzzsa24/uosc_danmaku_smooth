# Changelog

## 2.2.0-smooth.1

- Cache normalized ASS event text on first use.
- Cache ASS style prefixes and unchanged overlay state.
- Reduce allocations in the per-frame rendering loop.
- Replace the simplified/traditional conversion cache's shifting eviction with
  an O(1) FIFO queue.
- Update the conversion cache when `chConvert` changes.
- Publish repeatable rendering and parsing benchmarks.
- Require user-provided credentials for the official DanDanPlay API.
- Remove bundled shared DanDanPlay and TMDB credentials.
