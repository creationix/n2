## Purpose
This repository implements the N2 serialization format in multiple languages (TypeScript + Lua). The codebase contains two main implementations:
- `n2.ts` — reference encoder (in TypeScript). See `n2.test.ts` for expected byte-level encodings.
- `n2.lua` / `tibs.lua` — production-oriented Lua/LuaJIT implementation using ffi for performance and a ByteWriter abstraction.

When making changes, prefer keeping both implementations behaviorally identical. The TS files are useful for readable logic and tests; the Lua files are performance-critical and use pointer/ffi idioms.

Quick commands
- Run JS/TS unit tests (requires Bun):
  - bun test
- Run TypeScript type check (if you use tsc installed globally or as dev dep):
  - npx tsc --noEmit
- Run Lua tests (LuaJIT required):
  - luajit n2.test.lua
  - or run specific Lua scripts like `luajit test-encode.lua` when iterating on encoding.

Key patterns and conventions
- Reverse TLV: values are written first, then lengths/tags. Both encoders follow this reverse-TLV approach — changing write order breaks compatibility (see `n2.ts` encode() and `n2.lua` encode()).
- Varint headers: small numbers use a packed 1-byte (u5/zigzag) header; larger values use 2/3/5/9 byte encodings. See helper functions `writeUnsignedVarInt` / `writeSignedVarInt` in `n2.ts` and `encode_pair` / `encode_signed_pair` in `n2.lua`.
- Dedup / PTR optimization: Both implementations track seen values and may emit `PTR` instead of duplicating content. Look at `seen` / `seen_primitives` maps and the logic around estimating cost before emitting a pointer.
- Map encoding: object keys are encoded as a separate sub-value to enable schema sharing (see `encodeMap` in `n2.ts` and similar logic in `n2.lua`). Keys are sorted to provide deterministic outputs.

Files to inspect when changing behavior
- `n2.ts` — Reference encoder and unit tests (`n2.test.ts`) that assert exact hex encodings. Update/add TS tests when changing binary layout.
- `n2.test.ts` — Ground truth for many encodings. Use its `toHex` helper and expected hex strings as examples.
- `n2.lua`, `tibs.lua` — Production encoders/decoders. `tibs.lua` contains utilities (ByteWriter, Map/List abstractions) used by Lua-side code.
- `fixtures/encode.tibs` — Canonical encodings and patterns useful for creating additional tests and regression cases.

Development notes for AI agents
- Matching byte-level behavior is essential. When proposing changes to encoding logic, include updated unit tests in `n2.test.ts` and add or update corresponding fixture entries in `fixtures/`.
- Prefer small, incremental changes. The test suite contains many exact-hex assertions — use them to validate compatibility.
- For Lua changes, be mindful of ffi types and little-endian assumptions (the encoding relies on native endianness matching the spec). Use `luajit` for fast iteration.
- When suggesting API additions, keep the public surface minimal. The repo exposes `encode` (and a placeholder `decode`) in TS; mirror any API additions to Lua or document why they differ.

Examples to copy when writing tests or patches
- Add a TS test that calls `encode` and checks hex via `toHex(encode(...))` — see `n2.test.ts` for many examples.
- Reproduce a Lua regression by adding an entry to `fixtures/encode.tibs` or by running `luajit test-encode.lua` while iterating.

If anything in this file is unclear or you need more examples (specific failing tests, Lua run output, or CI details), tell me which area to expand and I will update this guidance.
