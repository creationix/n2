# N₂ v2 Format Specification

This document details the binary format, encoding rules, and type system of N₂ v2.

## 1. Format Overview

N₂ is written **backwards**. The decoder starts at the end of the file and reads backwards. This enables efficient append-only updates and random access without rewriting the file.

### 1.1 The Header Byte

Every value ends with a **Header Byte**:

```text
7   6   5   4   3   2   1   0
+---+---+---+---+---+---+---+---+
|   Type Tag    |  Size / Imm   |
+---+---+---+---+---+---+---+---+
```

*   **Type Tag** (4 bits): Identifies the type family (0-15).
*   **Size / Imm** (4 bits):
    *   **0-11**: Immediate value (for integers) or short byte length.
    *   **12**: 1-byte payload bytes follow (precede).
    *   **13**: 2-byte payload bytes follow.
    *   **14**: 4-byte payload bytes follow.
    *   **15**: 8-byte payload bytes follow.

### 1.2 Multi-Byte Values
All explicit integer payloads (for sizes 12-15) are **Little Endian**.
Signed integers use **Two's Complement**.

---

## 2. Type System

| Tag | Name | Description |
|:---:|:---|:---|
| **0** | `NUM` | Signed Integer |
| **1** | `DEC` | Decimal Number |
| **2** | `STR` | UTF-8 String |
| **3** | `BIN` | Binary Data |
| **4** | `PTR` | Pointer (Reuse) |
| **5** | `REF` | Reference (Constant) |
| **6** | - | *Reserved* |
| **7** | - | *Reserved* |
| **8** | `LST` | List |
| **9** | `MAP` | Map (Key-Value) |
| **A** | `CAT` | Concatenate (Rope) |
| **B** | `SCH` | Schema Pointer |
| **C** | `IDX` | Index Table (Metadata) |
| **D** | - | *Reserved* |
| **E** | - | *Reserved* |
| **F** | - | *Reserved* |

---

## 3. Detailed Layouts

All layouts are described in **memory order** (Low Address -> High Address). The Header Byte is always at the *highest* address (the end).

### 3.1 `NUM` (0) - Signed Integer

*Payload determined by lower 4 bits (S)*:

*   **S = 0..11**: Immediate Unsigned Int (Value = S).
*   **S = 12**: `[Int8] [Header]`
*   **S = 13**: `[Int16] [Header]`
*   **S = 14**: `[Int32] [Header]`
*   **S = 15**: `[Int64] [Header]`

### 3.2 `DEC` (1) - Decimal Scale

A modifier that applies to the **immediately following value** (in read order / preceding in memory).
It specifies a decimal scale `N`, such that the logical value is `NextValue * 10^-N`.

*   **S = 0..11**: Scale = S.
*   **S = 12..15**: Scale stored in payload.
    *   `[Scale] [Header]`

**Usage**:
*   Must be followed by a `NUM` (or `PTR/REF` resolving to `NUM`).
*   Example: `3.14` is encoded as `DEC(2)` then `NUM(314)`.
*   Example: `DEC(0)` can be used to explicitly tag an Integer as a Decimal type.

### 3.3 `STR` (2) / `BIN` (3) - String / Binary

*Payload determined by lower 4 bits (S)*:

*   **S = 0..11**: Length is `S`. Body follows immediately.
    *   `[Bytes...] [Header]`
*   **S = 12..15**: Length is stored in payload (1/2/4/8 bytes).
    *   `[Bytes...] [Length] [Header]`

### 3.4 `PTR` (4) - Pointer

Points to a value that appeared earlier in the stream.
*Value = Offset to subtract from current position.*

*   **S = 0..11**: Unused.
*   **S = 12..15**: Offset size (1/2/4/8 bytes).
    *   `[Offset] [Header]`

### 3.5 `REF` (5) - Reference

Index into a built-in or external Dictionary.

*   **S = 0..11**: Index = S.
*   **S = 12..15**: Index stored in payload.
    *   `[Index] [Header]`

**Built-ins**:
*   `0`: `null`
*   `1`: `true`
*   `2`: `false`
*   `3`: `delete` (Tombstone for Map merging)

### 3.6 `LST` (8) - List

Simple list of values. Values are written in reverse order.

*   **Layout**: `[Values...] [ByteLength] [Header]`

**Indexing Support**:
If the **first value** inside the list is `IDX` (Tag C), it indexes the rest.
*   `[Values...] [IDX] [Header]`

### 3.7 `MAP` (9) - Key-Value Map

Classic Map. Interleaved Keys and Values. `Key1, Val1, Key2, Val2...` (Written reverse: `Val2, Key2, Val1, Key1`).

*   **Layout**: `[Key] [Val] ... [ByteLength] [Header]`

**Schema Support**:
If the **first value** inside the map is `SCH` (Tag B), the keys are implied.
*   `[Values...] [SCH] [Header]`

### 3.8 `CAT` (A) - Concatenate (Rope)

Combines two or more values of the same type (List+List, String+String, Map+Map).

*   **Layout**: `[ValueN] ... [Value2] [Value1] [ByteLength] [Header]`
*   **Best For**: Appending to large lists/strings without rewriting.
*   **Map Behavior**: If a key in `Value1` maps to `REF(3)` (delete), it removes that key from the logical result.

### 3.9 `SCH` (B) - Schema Pointer

A wrapper around a Pointer, pointing to an existing List of keys.

*   **Layout**: `[SchemaPTR] [Header]`
*   **SchemaPTR**: A standard `PTR` (Tag 4).

### 3.10 `IDX` (C) - Index Table

A metadata value containing a table of offsets.

*   **Layout**: `[Offset N] ... [Offset 0] [ConfigByte] [Header]`
*   **Header**: Encodes the total byte length of the body.
*   **ConfigByte**: `[Count:6] [Width:2]`

---

## 4. Encoding Examples

The notation `<Hex>` indicates binary output. `XX` indicates variable payload bytes.

### 4.1 Primitives

**Integers (`NUM`)**
*   `0` -> `<00>` (Tag 0, Imm 0)
*   `10` -> `<0A>` (Tag 0, Imm 10)
*   `42` -> `<2A 0C>` (Tag 0, Size 12=1B, Val 42)
*   `-1` -> `<FF 0C>` (Tag 0, Size 12=1B, Val -1)
*   `1000` -> `<E8 03 0D>` (Tag 0, Size 13=2B, Val 1000)

**Decimals (`DEC`)**
*   `3.14` (`314 * 10^-2`)
    *   Base: `314` -> `<3A 01 0D>` (NUM, 2B, 314).
    *   Scale: `2` -> `<12>` (DEC, Imm 2).
    *   Result: `<3A 01 0D 12>`.
*   `1.1` (`11 * 10^-1`)
    *   Base: `11` -> `<0B>` (NUM, Imm 11).
    *   Scale: `1` -> `<11>` (DEC, Imm 1).
    *   Result: `<0B 11>`. (2 Bytes!).

**Strings (`STR`)**
*   `"hi"` (Length 2)
    *   Tag 2, Imm 2 -> `<22>`
    *   Result: `<68 69 22>` (`'h' 'i' [Head]`)

**Constants (`REF`)**
*   `null` (Index 0) -> `<50>` (Tag 5, Imm 0)
*   `true` (Index 1) -> `<51>` (Tag 5, Imm 1)
*   `false` (Index 2) -> `<52>` (Tag 5, Imm 2)
*   `delete` (Index 3) -> `<53>` (Tag 5, Imm 3)

### 4.2 Containers

**List (`LST`)**
*   `[10, 20]`
*   Values written reverse: `20`, `10`.
    *   `20`: `<14 0C>` (Tag 0, Size 1B, Val 20)
    *   `10`: `<0A>` (Tag 0, Imm 10)
*   Body: `<14 0C 0A>`. Length 3.
*   Header: Tag 8, Imm 3 -> `<83>`.
*   Result: `<14 0C 0A 83>`

**Map (`MAP`)**
*   `{"a": 1}`
*   Written reverse: `Val(1)`, `Key("a")`.
    *   `1`: `<01>` (Tag 0, Imm 1)
    *   `"a"`: `<61 21>` (Tag 2, Imm 1, 'a')
*   Body: `<01 61 21>`. Length 3.
*   Header: Tag 9, Imm 3 -> `<93>`
*   Result: `<01 61 21 93>`

**Schema Map (`MAP` + `SCH`)**
*   Assume specific memory layout for example:
    *   Keys `["x", "y"]` written previously at offset 0.
        *   `Key "y"`: `<79 21>`. `Key "x"`: `<78 21>`.
        *   List: `<79 21 78 21 84>` (Len 4).
*   Current Offset: 5.
*   Object: `{x: 10, y: 20}`.
*   Schema Pointer: Points to offset 0. `Delta = 5`.
    *   `PTR(5)`: Tag 4, Imm 5 -> `<45>`.
    *   `SCH` Wrapper: Tag B, Imm 1 (Len of PTR) -> `<B1>`.
    *   `SCH` Block: `<45 B1>`.
*   Values written reverse: `y(20)`, `x(10)`.
    *   `20`: `<14 0C>`.
    *   `10`: `<0A>`.
*   Map Body: `[20]`, `[10]`, `[SCH]`.
    *   `<14 0C 0A 45 B1>`. Total 5 bytes.
*   Map Header: Tag 9, Imm 5 -> `<95>`.
*   Result: `<14 0C 0A 45 B1 95>`

### 4.3 Indexing (`IDX`)

**Indexed List**
*   List `[v0, v1]`.
*   `v1` (`20`): `<14 0C>` (2 bytes).
*   `v0` (`10`): `<0A>` (1 byte).
*   Offsets (from end of Index):
    *   `v1` starts at -2.
    *   `v0` starts at -3 (`2 + 1`).
    *   Offsets: `2`, `3`.
*   Index Body: `[02] [03]`.
*   Config: Count 2, Width 1 (1B). `(2<<2)|0` = `0x08`.
*   IDX Body: `<02 03 08>`. Len 3.
*   IDX Header: Tag C, Imm 3 -> `<C3>`.
*   Result: `...values... <C3>`

---

## 5. Assembly Syntax

*   `(NUM 42)`
*   `(STR "hi")`
*   `(LST (NUM 1) (NUM 2))`
*   `(MAP (STR "a") (NUM 1))`
*   `(IDX <offsets...>)`
