# Changelog

## 2.2.0-smooth.3

- Record the download timestamp for each cached danmaku file.
- Refresh and overwrite cached comments after five hours.
- Reuse the cached episode ID for refreshes to avoid repeating title or hash matching.

## 2.2.0-smooth.2

- Cache successful DanDanPlay comment responses in one file per video.
- Reuse cached comments before automatic matching or downloading.
- Retain the manual search keyword and matched episode metadata with each cache.
- Remove cache files that have not been used for 30 days.

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
