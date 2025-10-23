# N₂: Data, Distilled

![N2 Logo](www/n2logo.jpg)

[![N2 LuaJIT Tests](https://github.com/creationix/n2/actions/workflows/lua-tests.yaml/badge.svg?event=push)](https://github.com/creationix/n2/actions/workflows/lua-tests.yaml)
[![N2 Bun Tests](https://github.com/creationix/n2/actions/workflows/bun-tests.yaml/badge.svg?event=push)](https://github.com/creationix/n2/actions/workflows/bun-tests.yaml)

**N₂** (nitrogen) is a highly efficient binary serialization format designed for modern applications that need **fast random access**, **compact storage**, and **incremental updates**.

## Key Features

N₂ solves common problems with traditional serialization formats like JSON, MessagePack, or Protocol Buffers:

- 📖 **Random Access**: Read specific parts of large datasets without parsing the entire file
- 🗜️ **Space Efficient**: Aggressive deduplication and compact encoding reduce file sizes significantly
- ⚡ **Incremental Updates**: Fetch only what changed between versions (cache-friendly)
- 🔄 **Atomic Versioning**: Instant activation or rollback of data versions via append-only structure
- 🖥️ **Machine Native**: Integers stored as native C types for zero-copy decoding

---

## Format Overview

N₂ uses a **reverse TLV** (Type-Length-Value) encoding: values are written first, then their length, then the type header. This enables efficient forward iteration and random access.

### Variable-Length Integer Encoding

To keep the format compact, N₂ uses variable-length integers. The **last byte** contains:

- **Upper 3 bits**: Type tag (8 possible types)
- **Lower 5 bits**: Either the value directly (0-27) or a size indicator for extended bytes

**Encoding sizes:**

```text
U5/Z5:  1 byte  → 0-27 unsigned, or -14 to +13 signed (zigzag)

  ttt xxxxx (where xxxxx < 11100)

U8/I8:  2 bytes → 0-255 unsigned, or -128 to +127 signed

  xxxxxxxx
  ttt 11100

U16/I16: 3 bytes → 64K unsigned, or ±32K signed

  xxxxxxxx xxxxxxxx
  ttt 11101

U32/I32: 5 bytes → 4M unsigned, or ±2M signed

  xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
  ttt 11110

U64/I64: 9 bytes → 16E unsigned, or ±8E signed

  xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
  xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
  ttt 11111
```

All multi-byte values use **little-endian** byte order.

### Core Type Tags

N₂ has 8 fundamental type tags:

| Type | Description | Use Case |
|------|-------------|----------|
| `NUM` | Signed integers | Numbers in the i64 range |
| `STR` | UTF-8 strings | Text data |
| `BIN` | Binary data | Raw bytes, blobs |
| `LST` | Lists/arrays | Ordered collections |
| `MAP` | Key-value maps | Objects with keys encoded as a sub-value array |
| `PTR` | Pointers | References to existing values (deduplication) |
| `REF` | External references | Built-in constants or shared dictionary |
| `EXT` | Extension data | Type modifiers (e.g., decimals, string chains) |

### Built-in Constants

Three values are always available via `REF`:

```text
REF(0) → nil
REF(1) → true
REF(2) → false
REF(3+) → user-defined dictionary entries
```

### Value Types

Various values are encoded using the 7 core types combind with zero or more `EXT` tags.

| Name         | Encoding                         | Interpretation                               |
|--------------|----------------------------------|----------------------------------------------|
| Integer      | `NUM(val:i64)`                   | `val` is the integer itself.                 |
| Decimal      | `EXT(pow:i64)`<br>`NUM(val:i64)` | `pow` is a power of 10.<br>`val` is the base value. |
| Pointer      | `PTR(off:u64)`                   | `off` is the relative byte offset between the `PTR` and target. |
| Reference    | `REF(idx:u64)`                   | `idx` is the index into a table of known values. |
| Bytes        | `BIN(len:u64)`<br>`BYTES`        | `len` is the number of bytes.<br>`BYTES` is the value itself. |
| String       | `STR(len:u64)`<br>`BYTES`        | `len` is the number of bytes.<br>`BYTES` is the string as utf-8. |
| String Chain | `EXT(cnt:u64)`<br>`STR(len:u64)`<br>`VALUE*` | `cnt` is the _(redundant)_ count of string segments. <br>`len` is the number of bytes of all children.<br>`VALUE*` is zero or more strings, pointers, or recursive chains. |
| List         | `LST(len:u64)`<br>`VALUE*`       | `len` is the number of bytes of all children.<br>`VALUE*` is zero or more recursive values. |
| Array        | `EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`LST(len:u64)`<br>`INDEX`<br>`VALUE*` | `wid` is index pointer width.<br>`cnt` is count of index entries<br>`len` is the number of bytes of all children.<br>`INDEX` is an array of fixed width offset pointers _(from end of index)_<br>`VALUE*` is zero or more recursive values. |
| Map          | `MAP(len:u64)`<br>`(KEY VALUE)*` | `len` is the number of bytes of all children<br>`(KEY VALUE)*` is zero or more recursive key-value pairs. |
| Schema Map   | `EXT(off:u64)`<br>`MAP(len:u64)`<br>`SCHEMA?`<br>`VALUE*` | `off` is the relative offset between the `EXT` and the shared schema<br>`len` is the number of bytes of all children.<br>`SCHEMA?` is a recursive List or Array of key values set on first use.<br>`(KEY VALUE)*` is zero or more recursive key-value pairs. |
| Binary Map   | `EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`MAP(len:u64)`<br>`INDEX`<br>`(KEY VALUE)*` | `wid` is index pointer width.<br>`cnt` is count of index entries<br>`len` is the number of bytes of all children.<br>`INDEX` is an array of fixed width offset pointers _(from end of index)_<br>`(KEY VALUE)*` is zero or more sorted recursive key-value pairs. |

## Type Encoding Examples

The following examples show how different data types are encoded. The notation `↩` indicates "encodes to" and shows the encoding layers from logical value down to bytes.

### NUM - Integer Numbers

Integers use **signed** variable-length encoding (zigzag for small values):

```lua
-- Small values fit in the type header
0 ↩
  NUM(0) ↩
    Z5(NUM,0) ↩
    U5(NUM,0) ↩
      00000 NUM

5 ↩
  NUM(5) ↩
    Z5(NUM,5) ↩
    U5(NUM,10) ↩
      01010 NUM

-- Larger values use extended bytes
-42 ↩
  NUM(-42) ↩
    I8(NUM,-42) ↩
    U8(NUM,214) ↩
      11010110 11110 NUM

314 ↩
  NUM(314) ↩
    I16(NUM,314) ↩
    U16(NUM,314) ↩
      00111010 00000001 11101 NUM
```

### NUM + EXT - Decimal Numbers

Decimals are encoded as **base × 10^exponent** using `NUM` for the base and `EXT` for the signed exponent:

```lua
3.14 ↩
  NUM(314) EXT(-2) ↩    -- 314 × 10^-2
    I16(NUM,314) Z5(EXT,-2) ↩
    U16(NUM,314) U5(EXT,3) ↩
      00111010 00000001 11101 NUM 00011 EXT
```

### REF - Constants and Dictionary References

Use `REF` for built-in constants or shared dictionary values:

```lua
nil ↩
  REF(NIL) ↩
    U5(REF,NIL) ↩
      NIL REF

true ↩
  REF(TRUE) ↩
    U5(REF,TRUE) ↩
      TRUE REF

false ↩
  REF(FALSE) ↩
    U5(REF,FALSE) ↩
      FALSE REF

-- Dictionary value at index 20 (offset by 3 built-ins)
sharedDictionary[20] ↩
  REF(USER + 20) ↩
  REF(23) ↩
    U5(REF,23) ↩
      10111 REF
```

### STR - UTF-8 Strings

String length is in bytes, not characters. Hex values show UTF-8 encoded content:

```lua
"" ↩
  STR(0) ↩
    U5(STR,0) ↩
      00000 STR

"hi" ↩
  <6869> STR(2) ↩
    <6869> U5(STR,2) ↩
      <6869> 00010 STR

"😁" ↩    -- 4-byte UTF-8 emoji
  <f09f9881> STR(4) ↩
    <f09f9881> U5(STR,4) ↩
      <f09f9881> 00100 STR
```

### BIN - Binary Data

Identical to `STR` but for arbitrary bytes:

```lua
<deadbeef> ↩
  <deadbeef> BIN(4) ↩
    <deadbeef> U5(BIN,4) ↩
      <deadbeef> 00100 BIN
```

### PTR - Pointers for Deduplication

Pointers reference earlier values using a **negative byte offset** from the current position:

```lua
-- Pointer to a value 8 bytes back
*greeting ↩
  PTR(50 - 42) ↩    -- From offset 50 to target at offset 42
  PTR(8) ↩
    U5(PTR,8) ↩
      01000 PTR

-- Duplicate value: write once, then point to it
5 5 ↩
  NUM(5) PTR(0) ↩    -- Second "5" points to first (0 bytes away)
    U5(NUM,10) U5(PTR,0) ↩
      01010 NUM 00000 PTR
```

### LST - Lists/Arrays

Lists encode their **total byte length** (not item count) and write items in **reverse order** to enable forward iteration:

```lua
[1, 2, 3] ↩
  NUM(3) NUM(2) NUM(1) LST(3) ↩    -- Items reversed, length = 3 bytes
    Z5(NUM,3) Z5(NUM,2) Z5(NUM,1) U5(LST,3) ↩
    U5(NUM,6) U5(NUM,4) U5(NUM,2) U5(LST,3) ↩
      00110 NUM 00100 NUM 00010 NUM 00011 LST
```

### MAP - Key-Value Maps

Maps write **values first** (in reverse order), then **keys as a sub-value** (array), then the MAP header. This allows the key array to be deduplicated when multiple objects share the same structure:

```lua
{ "name": "N2" } ↩
  STR("N2") LST(["name"]) MAP(8) ↩    -- Value, then keys array, then MAP
    <4e32> U5(STR,2) <6e616d65> U5(STR,4) U5(LST,5) U5(MAP,9) ↩
      <4e32> 00010 STR <6e616d65> 00100 STR 00101 LST 01001 MAP

{ "a": 1, "b": 2 } ↩
  NUM(2) NUM(1) LST(["a","b"]) MAP(7) ↩    -- Values reversed, then keys
    24 22 <62> U5(STR,1) <61> U5(STR,1) U5(LST,4) U5(MAP,7) ↩
      24 22 62 41 61 41 84 a7
```

### Automatic Schema Deduplication

When encoding multiple objects with the same keys, the encoder automatically deduplicates the key arrays using `PTR`. This happens naturally because keys are encoded as a separate sub-value:

```lua
-- Two objects with same keys ["a", "b"]
[ { "a": 1, "b": 2 }, { "a": 3, "b": 4 } ] ↩

-- First object encodes keys, second object points to them
  NUM(4) NUM(3) LST(["a","b"]) MAP(7) ↩      -- First object: full encoding
  NUM(2) NUM(1) PTR(keys) MAP(3) ↩           -- Second object: reuses keys via pointer
  LST(12) ↩

-- Actual bytes:
  28 26                    -- Values: 4, 3 (reversed)
  62 41 61 41 84           -- Keys: ["b", "a"] as LST(4)
  a7                       -- MAP(7)
  24 22                    -- Values: 2, 1 (reversed)
  c3                       -- PTR(3) points back 3 bytes to keys array
  a3                       -- MAP(3)
  8c                       -- LST(12)
```

This automatic deduplication works for any number of objects with shared structure. The fourth object with keys `["a", "b"]` would use `PTR` to point back to the first object's key array.

### Future Extensions

The `EXT` type is reserved for additional features:

- `STR + EXT`: String chains for substring deduplication
- And more to come...

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

### Key Conventions

Both implementations follow these core principles:

1. **Reverse TLV Encoding**: Values written first, then length/tags
2. **Automatic Deduplication**: `PTR` used for repeated values, including object key arrays
3. **MAP Structure**: Keys encoded as a separate sub-value (array) to enable schema sharing
4. **Deterministic Output**: Sorted map keys ensure consistent encoding
5. **Little-Endian**: All multi-byte values use little-endian byte order

---

## Use Cases

N₂ is ideal for:

- **Configuration Management**: Store app configs with atomic rollback capability
- **Data Distribution**: Efficiently sync large datasets with incremental updates
- **Caching**: Compact storage with fast random access to specific values
- **Game Save Files**: Versioned, compact saves with instant load/rollback
- **API Responses**: Bandwidth-efficient alternative to JSON with deduplication

---

## Contributing

When modifying the format or implementations:

1. Update tests in both TypeScript (`ts/n2.test.ts`) and Lua (`lua/n2.test.lua`)
2. Verify byte-level compatibility between implementations
3. Add test fixtures to `fixtures/encode.tibs` for new features
4. Keep encoding deterministic and backward-compatible

See `.github/copilot-instructions.md` for detailed development guidelines.

---

## License

This project is open source. See the repository for license details.
