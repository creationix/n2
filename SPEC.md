# N₂ Format Specification

This document details the binary format, encoding rules, and type system of N₂.

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

| Type  | Name      | Use Case                              |
|-------|-----------|---------------------------------------|
| `NUM` | Number    | Integer and decimal numbers           |
| `STR` | String    | UTF-8 encoded textual data            |
| `BIN` | Binary    | Raw 8-bit binary data                 |
| `LST` | List      | List of arbitrary values              |
| `MAP` | Map       | Lists of arbitrary key/value mappings |
| `PTR` | Pointer   | Pointers to existing values           |
| `REF` | Reference | Built-in or external constants        |
| `EXT` | Extended  | Type modifiers/extenders              |

### Built-in Constants

Three values are always available via `REF`:

```text
REF(0) → nil
REF(1) → true
REF(2) → false
REF(3) → delete (used to delete keys in append maps)
REF(4+) → user-defined dictionary entries
```

### Value Types

Various values are encoded using the 7 core types combined with zero or more `EXT` tags.

| Name          | Encoding                         | Interpretation                               |
|---------------|----------------------------------|----------------------------------------------|
| Integer       | `NUM(val:i64)`                   | `val` is the integer itself.                 |
| Decimal       | `EXT(pow:i64)`<br>`NUM(val:i64)` | `pow` is a power of 10.<br>`val` is the base value. |
| Pointer       | `PTR(off:u64)`                   | `off` is the relative byte offset between the `PTR` and target. |
| Reference     | `REF(idx:u64)`                   | `idx` is the index into a table of known values. |
| Bytes         | `BIN(len:u64)`<br>`BYTES`        | `len` is the number of bytes.<br>`BYTES` is the value itself. |
| Append Bytes  | `EXT(off:u64)`<br>`BIN(len:u64)`<br>`VALUE*` | `off` is optional pointer to a binary prefix.<br>`len` is the number of bytes of all children.<br>`VALUE*` is zero or more recursive binary values. |
| String        | `STR(len:u64)`<br>`BYTES`        | `len` is the number of bytes.<br>`BYTES` is the string as utf-8. |
| Append String | `EXT(off:u64)`<br>`STR(len:u64)`<br>`VALUE*` | `off` is optional pointer to a string prefix.<br>`len` is the number of bytes of all children.<br>`VALUE*` is zero or more recursive string values. |
| List          | `LST(len:u64)`<br>`VALUE*`       | `len` is the number of bytes of all children.<br>`VALUE*` is zero or more recursive values. |
| Append List   | `EXT(off:u64)`<br>`LST(len:u64)`<br>`VALUE*` | `off` is optional pointer to a list prefix.<br>`len` is the number of bytes of all children.<br>`VALUE*` is zero or more recursive values. |
| Indexed List  | `EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`LST(len:u64)`<br>`INDEX`<br>`VALUE*` | `wid` is index pointer width.<br>`cnt` is count of index entries<br>`len` is the number of bytes of all children.<br>`INDEX` is an array of fixed width offset pointers _(from end of index)_<br>`VALUE*` is zero or more recursive values. |
| Indexed Append List | `EXT(off:u64)`<br>`EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`LST(len:u64)`<br>`INDEX`<br>`VALUE*` | Combined capabilities of Append List and Indexed list |
| Map           | `MAP(len:u64)`<br>`(KEY VALUE)*` | `len` is the number of bytes of all children<br>`(KEY VALUE)*` is zero or more recursive key-value pairs. |
| Append Map    | `EXT(off:u64)`<br>`MAP(len:u64)`<br>`(KEY VALUE)*` | `off` is optional pointer to a map prefix.<br>`len` is the number of bytes of all children.<br>`(KEY VALUE)*` is zero or more recursive key-value pairs. |
| Indexed Map   | `EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`MAP(len:u64)`<br>`INDEX`<br>`(KEY VALUE)*` | `wid` is index pointer width.<br>`cnt` is count of index entries<br>`len` is the number of bytes of all children.<br>`INDEX` is an array of fixed width offset pointers _(from end of index)_<br>`(KEY VALUE)*` is zero or more sorted recursive key-value pairs. |
| Indexed Append Map | `EXT(off:u64)`<br>`EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`MAP(len:u64)`<br>`INDEX`<br>`(KEY VALUE)*` | Combined capabilities of Append Map and Indexed Map |
| Schema Map    | `EXT(off:u64)`<br>`MAP(len:u64)`<br>`SCHEMA?`<br>`VALUE*` | `off` is the relative offset between the `EXT` and the shared schema list.<br>`len` is the number of bytes of all children.<br>`SCHEMA?` is a recursive List of key values set on first use.<br>`VALUE*` is zero or more recursive values. |
| Indexed Schema Map | `EXT(off:u64)`<br>`EXT(wid:u64)`<br>`EXT(cnt:u64)`<br>`MAP(len:u64)`<br>`INDEX`<br>`SCHEMA?`<br>`VALUE*`| Combined capabilities of Schema Map and Indexed Map| `off` is the relative offset between the `EXT` and the shared schema list.<br>`len` is the number of bytes of all children.<br>`SCHEMA?` is a recursive List of key values set on first use.<br>`VALUE*` is zero or more recursive values. |

### Understanding the Type System

While the table above shows many value types, the design follows elegant patterns that make it simple to understand and implement.

#### Decoding Pattern

Decoders use a straightforward two-step process:

1. **Read all consecutive `EXT` tags** until reaching a non-EXT type
2. **Pattern match** on the EXT count and base type

This creates an unambiguous, self-describing format where the number of EXT tags determines the interpretation:

| EXT Count | Base Type | Interpretation | Parameters |
|-----------|-----------|----------------|------------|
| 0 | `NUM` | Integer | value is the integer |
| 1 | `NUM` | Decimal | `ext₀` = power of 10, `NUM` = base value |
| 1 | `STR/BIN/LST` | Append | `ext₀` = offset to prefix (or 0 for chains) |
| 1 | `MAP` | Append or Schema* | `ext₀` → MAP (append) or LST (schema) |
| 2 | `LST/MAP` | Indexed | `ext₀` = index width, `ext₁` = count |
| 3 | `LST/MAP` | Indexed Append or Indexed Schema* | `ext₀` = offset, `ext₁` = width, `ext₂` = count |

*Disambiguated by following the pointer: MAP target = append variant, LST target = schema variant

#### Why This Is Elegant

**Composability Without Flags**: Instead of using bit flags or mode bytes to indicate features, N₂ uses the *count* of EXT tags. Want an indexed list? Add two EXTs. Want indexed *and* append? Add three EXTs. This means:

- No wasted bytes on feature flags
- Clear parity pattern: odd EXT counts have append pointers, even counts don't
- Extensible to 4-EXT, 5-EXT patterns without breaking existing decoders

**Self-Describing Types**: The format disambiguates using the type system itself. When you see `EXT + MAP`, following the pointer tells you what variant it is:

- Points to `MAP` → Append Map (incremental updates)
- Points to `LST` → Schema Map (shared keys)

No additional type bits needed.

**Schema As Value**: Schema maps store their key list as a regular value in the value stream. When decoding:

1. Follow `EXT(off)` to find the schema `LST`
2. Parse all values in the map body
3. Skip any value whose byte offset equals `off` (it's the schema definition)
4. Remaining values are the data

This means:
- First use writes schema inline: `EXT:s MAP s:(LST keys...) values...`
- Subsequent uses point to the same schema: `EXT:s MAP values...` (no schema inline)
- Decoder doesn't care where schema lives, just skips it if present
- Natural deduplication without special cases or external schema registries

**Minimal Core, Maximum Power**: The entire type system is built from just 8 core types and one extension mechanism (`EXT`), yet it can express:

- Efficient primitives (integers, decimals, strings, binary data)
- Structural sharing via pointers (`PTR`, `REF`)
- Incremental updates (append variants)
- Random access (indexed variants)
- Schema sharing (schema maps)
- All combinations through composition

## Assembly Syntax

Sometimes a textual representation is useful for understanding how a document is optimized/structured.

- String uses JSON syntax
  - For example `"Hello"`
- Bytes use `<` + hex + `>` and allow whitespace and comments between bytes.
  - For example `<deadbeef>`
- Unsigned Integers use normal decimal syntax with `/` in front.
  - For example `/123`.  But also `/NIL`, `/TRUE`, `/FALSE`, and `/DELETE` can be used
- Signed Integers use normal decimal syntax with an explicit `+` or `-`
  - For example `+123` or `-3`
- Pointers use `*`+name syntax and point to locations using name+`:` labels outside the target.
  - For example `(PTR*a) ... a:(NUM+42)`
- When a tag contains a length, no value is written, but the body they contain is inside the parentheses.
  - For example `(STR "Hello")`
- When `EXT` contains zero, it's just written `EXT`.
- The distinction between the 5 varint representations is abstracted away at this level.
- An array index is written as `###`
- The width param is written as `EXT/w`
- The count param is written as `EXT/c`
- When showing that arbitrary data might exist, `...` is used.

```lua
-- Encoding the integer 42 looks like this:
(NUM+42)
-- Encoding the decimal value 3.14 (314e-2) looks like this:
(EXT-2 NUM+314)
-- Encoding [1, 2, 3] looks like:
(LST (NUM+1) (NUM+2) (NUM+3))
-- Encoding "Hello World" as a single string looks like:
(STR "Hello World")
-- Encoding it as a two segment string chain looks like:
(EXT STR (STR "Hello") (STR " World"))
-- Encoding the two segments using an append pointer looks like:
(EXT:w STR (STR " World")) ... w:(STR "Hello")
-- Encoding {name:"N2"} looks like:
(MAP (STR "name") (STR "N2"))
-- But if it has an external schema it looks like:
(EXT:s MAP (STR "N2")) ... s:(LST (STR "name"))
-- Or if the shared schema is inside, it looks like:
(EXT:s MAP s:(LST (STR "name")) (STR "N2"))
-- An append list that decodes to [2,false,1,true] might look like:
(EXT:p LST (NUM+1) (REF/1)) ... p:(LST (NUM+2) (REF/2))
-- An indexed map for {a:1,b:2,c:3} might look like:
(EXT/w EXT/c MAP ### (STR "a") (NUM+1) (STR "b") (NUM+2) (STR "c") (NUM+3))
-- And finally, an append indexed map for updating a value
-- The original document was {name:"Bob",happy:false,problems:99},
original:(MAP (STR "name") (STR "Bob") (STR "happy") (REF/FALSE) (STR "problems") (NUM+99))
-- but we want to make him happy and take his problems away so we append {happy:true,problems:delete}
(EXT:original MAP (STR "problems") (REF/DELETE) (STR "happy") (REF/TRUE))
```

If preferred, the assembly can be written in reverse to match the binary encoding order.

```lua
(("N2" STR) (("name" STR) LST):s MAP s:EXT)
```

## Type Encoding Examples

The following examples show how different data types are encoded. The notation `↩` indicates "encodes to" and shows the encoding layers from logical value down to bytes.

### NUM - Integer Numbers

Integers use **signed integer** variable-length encoding directly.  The larger the number, the larger the representation needed.

| Value     | N2 Assembly    | N2 Binary       |
|-----------|----------------|-----------------|
| `0`       | `(NUM+0)`      | `<00>`          |
| `-10`     | `(NUM-10)`     | `<13>`          |
| `100`     | `(NUM+100)`    | `<64 1c>`       |
| `-1000`   | `(NUM-1000)`   | `<18fc 1d>`     |
| `10000`   | `(NUM+10000)`  | `<1027 1d>`     |
| `-100000` | `(NUM-100000)` | `<6079feff 1e>` |

### NUM + EXT - Decimal Numbers

Decimals are encoded as **base × 10^exponent** using `NUM` for the base and `EXT` for the signed exponent.

| Value     | N2 Assembly       | N2 Binary      |
|-----------|-------------------|----------------|
| `0.0001`  | `(EXT-4 NUM+1)`   | `<02 27>`      |
| `-0.001`  | `(EXT-3 NUM-1)`   | `<01 25>`      |
| `0.01`    | `(EXT-2 NUM+1)`   | `<02 23>`      |
| `-0.1`    | `(EXT-1 NUM-1)`   | `<01 21>`      |
| `0`       | `(EXT+0 NUM+0)`   | `<00 20>`      |
| `-10`     | `(EXT+1 NUM-1)`   | `<01 22>`      |
| `100`     | `(EXT+2 NUM+1)`   | `<02 24>`      |
| `-1000`   | `(EXT+3 NUM-1)`   | `<01 26>`      |
| `10000`   | `(EXT+4 NUM+1)`   | `<02 28>`      |
| `-100000` | `(EXT+5 NUM-1)`   | `<01 2a>`      |
| `3.14`    | `(EXT-2 NUM+314)` | `<3a01 1d 23>` |

### REF - Constants and Dictionary References

Use `REF` for built-in constants or shared dictionary values.  The `delete` value is used to delete entries in append maps.

| Value     | N2 Assembly | N2 Binary |
|-----------|-------------|-----------|
| `nil`     | `(REF/0)`   | `<e0>`    |
| `true`    | `(REF/1)`   | `<e1>`    |
| `false`   | `(REF/2)`   | `<e2>`    |
| `delete`  | `(REF/3)`   | `<e3>`    |
| `user[2]` | `(REF/6)`   | `<e6>`    |

### STR - UTF-8 Strings

String length is in bytes, not characters.  Unicode is encoded as UTF-8.

| Value     | N2 Assembly    | N2 Binary       |
|-----------|----------------|-----------------|
| `""`      | `(STR/0)`      | `<40>`          |
| `"hi"`    | `(STR/2 "hi")` | `<6869 42>`     |
| `"😁"`     | `(STR/4 "😁")`  | `<f09f9881 44>` |

### EXT STR - String Chains (AKA Append Strings)

String chains are for substring deduplication.  In many datasets there is a lot of substrings that are shared in many places.

This extended type enables both linear and recursive combining of strings.

### BIN - Binary Data

Identical to `STR` but for arbitrary bytes:

| Value     | N2 Assembly        | N2 Binary       |
|-----------|--------------------|-----------------|
| `<>`      | `(BIN/0)`          | `<40>`          |
| `<123456> | `(BIN/3 <123456>)` | `<123456 43>`   |

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
