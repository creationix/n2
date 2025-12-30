# N₂: Data, Distilled

![N2 Logo](www/n2logo.jpg)

[![N2 LuaJIT Tests](https://github.com/creationix/n2/actions/workflows/lua-tests.yaml/badge.svg?event=push)](https://github.com/creationix/n2/actions/workflows/lua-tests.yaml)
[![N2 Bun Tests](https://github.com/creationix/n2/actions/workflows/bun-tests.yaml/badge.svg?event=push)](https://github.com/creationix/n2/actions/workflows/bun-tests.yaml)

**N₂** (Nitrogen) is a binary format designed for **instant access to massive datasets**. It enables applications—especially remote workers, edge functions, and CLI tools—to query gigabytes of data with **near-zero startup latency** by reading only the bytes strictly required for the query.

### The Problem: Latency at Scale
Loading large datasets (e.g., 500MB+) in serverless environments or remote workers is prohibitive. Traditional formats like JSON, MessagePack, or Protocol Buffers require **parsing the entire file** before you can access a single value. This causes massive CPU and memory spikes, killing cold-start performance.

### The Solution: On-Demand Access
N₂ eliminates this bottleneck using a **Reverse TLV** architecture and separate schema storage:

- ⚡ **Zero-Parse Startup**: "Open" a 10GB file and read a nested value in microseconds.
- 📡 **Network Efficient**: Fetch *only* the byte ranges needed for your query (perfect for HTTP Range requests).
- 💾 **Lazy Loading**: Complete massive datasets can be accessed virtually, with data loaded bit-by-bit only when requested.
- 🔄 **Incremental Updates**: Modify data by appending to the end of the file—no expensive rewrites.

### Architecture: Dumb Server, Smart Client
N₂ shifts the "database engine" from the server to the client. Instead of a running database process (Postgres, SQLite) that burns CPU parsing queries, N₂ allows you to host your data on **dumb, static storage** (S3, R2, CDN).

- **Server**: Serves raw bytes via HTTP Range requests. Zero CPU overhead. Infinite scalability.
- **Client**: Uses the cached N₂ index to know exactly which bytes to fetch.
- **Result**: The first lookup takes ~2 RTTs. Every subsequent lookup is **1 RTT** (just fetching bytes), bypassing backend logic entirely.

---

## Use Cases

N₂ is ideal for:

- **Configuration Management**: Store app configs with atomic rollback capability
- **Data Distribution**: Efficiently sync large datasets with incremental updates
- **Caching**: Compact storage with fast random access to specific values
- **Game Save Files**: Versioned, compact saves with instant load/rollback
- **API Responses**: Bandwidth-efficient alternative to JSON with deduplication

---

## Implementations

This repository contains N₂ encoders in multiple languages:

### TypeScript (Reference Implementation)

- **Location**: `ts/n2.ts`
- **Tests**: `ts/n2.test.ts`
- **Runtime**: Bun
- **Purpose**: Reference encoder with comprehensive test suite

Run TypeScript tests:

```bash
cd ts && bun test
```

### Lua (Production Implementation)

- **Location**: `lua/n2.lua`
- **Tests**: `lua/n2.test.lua`
- **Runtime**: LuaJIT
- **Purpose**: High-performance encoder using FFI for native performance

Run Lua tests:

```bash
luajit lua/n2.test.lua
```

---

## Specification

For detailed information on the binary format, type system, and encoding rules, please see [SPEC.md](SPEC.md).
