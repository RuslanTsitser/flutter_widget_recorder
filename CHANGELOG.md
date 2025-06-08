# Changelog

## [Unreleased]

### Fixed

- Corrected pixel buffer alignment for iOS video recording: now frames are padded to sizes compatible with H.264 codec requirements (multiples of 16).
- Fixed stride handling for incoming pixel data to support non-standard row sizes from Flutter.
- Eliminated errors related to mismatched frame and buffer sizes, preventing crashes and black frames.
- Improved error diagnostics and logging for frame capture and writer failures.

### Changed

- Now uses `pixelWidth` and `pixelHeight` (aligned sizes) for all AVAssetWriter and buffer operations.
- Fills extra buffer space (right and bottom) with black pixels to match codec requirements.
- Simplified and clarified the logic for copying and converting pixel data from Flutter to native iOS buffers.

### Added

- Additional error messages for invalid stride and buffer creation failures.
- Comments and documentation in the Swift code for easier maintenance.

---

## [Older versions]

- See previous commit history for earlier changes.
