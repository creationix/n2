# N₂: Data, Distilled

![N2 Logo](www/n2logo.jpg)

[![N2 LuaJIT Tests](https://github.com/creationix/n2/actions/workflows/test.yaml/badge.svg?event=push)](https://github.com/creationix/n2/actions/workflows/test.yaml)

N₂ is short for nitrogen, a simple and essential gas.  It is also a new and exciting serialization protocol that enables random access and mutability via an append-only persistent data structure.

### Core Goals of the Design

- **Efficient Random Access**: Allow consumers to parse only the necessary parts of a large dataset without reading the entire file.
- **High Data Density**: Reduce total file size through aggressive deduplication of values/structures and compact object schemas.
- **Cache-Friendly Incremental Updates**: Enable consumers to fetch only the delta when a new version of the dataset is published.
- **Atomic Version Switching**: Allow for instantaneous activation or rollback of datas
- **Machine Friendly**: Most integers are stored directly as native c-types *(`i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64`)* that can be decoded using memory pointer casting.

## Part 1: The Serialization Format

Every value is encoded using a reverse TLV (type-length-value) format where the value is written first, then the length, then the type header.

To save space in the serialized encoding a simple variable length integer format is used.  To decode, read the last byte first.  The upper 3 bits is the type tag.  The lower 5 bits is either the value (if less than 28) or a length type telling you to read 8, 16, 32, or 64 more bits for the integer.

Multi-byte values are stored in little-endian to match most host computers and web assembly.

```
U5/Z5 supports 0 to 27 for unsigned and -14 to 13 for zigzag signed

  ttt xxxxx (where xxxxx < 11100)

U8/I8 supports 0 to 255 for unsigned or -128 to 127 for 2s complement signed

  xxxxxxxx
  ttt 11100

U16/I16 supports 64Ki for unsigned or +- 32Ki for 2s complement signed

  xxxxxxxx xxxxxxxx
  ttt 11101

U32/I32 supports 4Mi for unsigned or +- 2Mi for 2s complement signed

  xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
  ttt 11110

U64/I64 supports 16Ei for unsigned or += 8Ei (I64) for 2s complement signed

  xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
  xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
  ttt 11111
```

There are 8 core types (using the 3 type bits) that can be paired with the signed and unsigned varints to form bytes

```lua
0 - EXT (data) signed or unsigned depending on context
1 - NUM (value) signed
2 - STR (length) unsigned
3 - BIN (length) unsigned
4 - LST (length) unsigned
5 - MAP (length) unsigned
6 - PTR (offset) unsigned
7 - REF (index) unsigned
```

And while producers and consumers of these files can agree on an external dictionary for use in the `REF` type, there are 3 built-in values always there

```lua
0 - nil (NIL)
1 - true (TRUE)
2 - false (FALSE)
3 - user_defined (USER)
```

### Types Explained

- `NUM` is for encoding integers in the `i64` range.  The signed variant of headers is used.

```lua
0 ->
  NUM(0) ->
    Z5(NUM,0) ->
    U5(NUM,0) ->
      00000 NUM

5 ->
  NUM(5) ->
    Z5(NUM,5) ->
    U5(NUM,10) ->
      01010 NUM

-42 ->
  NUM(-42) ->
    I8(NUM,-42) ->
    U8(NUM,214) ->
      11010110 11110 NUM

314 ->
  NUM(314) ->
    I16(NUM,314) ->
    U16(NUM,314) ->
      00111010 00000001 11101 NUM

-12456 ->
  NUM(-12345) ->
    I16(NUM,-12345) ->
    U16(NUM,51151) ->
      11000111 11001111 11101 NUM
```

- `NUM` + `EXT` is for encoding decimal values with `i64` base and `i64` power of 10.   For example `3.14` is encoded as `314e-2` which is `EXT(-2)` followed by `NUM(314)` which encodes in 4 bytes.

```lua
3.14 ->
  NUM(314) EXT(-2) ->
    I16(NUM,314) Z5(EXT,-2) ->
    U16(NUM,314) U5(EXT,3) ->
      00111010 00000001 11101 NUM 00011 EXT
```

- `REF` is used for primitives, but can also reference user values offsetting by 3

```lua
nil ->
  REF(NIL) ->
    U5(REF,NIL) ->
      NIL REF

true ->
  REF(TRUE) ->
    U5(REF,TRUE) ->
      TRUE REF

false ->
  REF(FALSE) ->
    U5(FALSE) ->
      FALSE REF

sharedDictionary[20] -> -- the 21st item in the 0-based dictionary array
  REF(USER + 20) ->
  REF(23) ->
    U5(REF,23) ->
      10111 REF
```

- `STR` is for encoding UTF-8 Strings

```lua
"" ->
  STR(0) ->
    U5(STR,0) ->
      00000 STR

"hi" ->
  <6869> STR(2) ->
    <6869> U5(STR,2) ->
      <6869> 00010 STR

"😁" ->
  <f09f9881> STR(4) ->
    <f09f9881> U5(STR,4) ->
      <f09f9881> 00100 STR
```

- `BIN` is the same, but encodes arbitrary binary data.

```lua
<deadbeef> ->
  <deadbeef> BIN(4) ->
    <deadbeef> U5(BIN,4) ->
      <deadbeef> 00100 BIN
```

- `PTR` is a pointer to an existing value in the document.  It is a negative byte offset from the start of this value.  The target is the high end of the target (where the head is).  The source offset if where we are about to write the ptr.

```lua
*greeting -- Pointer to target offset 42 from offset 50
  PTR(50 - 42)
  PTR(8)
    U5(PTR,8)
      01000 PTR

5 5 -- We want to encode a value twice
5->val *val -- ptr and target are touching, offset delta is 0
  NUM(5) PTR(0)
    U5(NUM,10) U5(PTR,0)
      01010 NUM 00000 PTR
```

- `LST` is for encoding lists of values.  The integer part is total byte length of all content (not count of item).  This enables fast skipping of values.  Also values are written in reverse order so they can be iterated in forward order.

```lua
[1, 2, 3] ->
  NUM(3) NUM(2) NUM(1) LST(3) ->
    Z5(NUM,3) Z5(NUM,2) Z5(NUM,1) U5(LST,3) ->
    U5(NUM,6) U5(NUM,4) U5(NUM,2) U5(LST,3) ->
      00110 NUM 00100 NUM 00010 NUM 00011 LST
```

- `MAP` is for encoding maps from keys to values. Unlike JSON, the keys can be any value (including `PTR` or `REF`).  The values are written in verse order with values before keys so that reading can iterate in forward order.

```lua
{ "name": "N2" } ->
  "N2" STR(2) "name" STR(4) MAP(8) ->
     <4e32> U5(STR,2) <6e616d65> U5(STR,4) U5(MAP,8) ->
       <4e32> 00010 STR <6e616d65> 00100 STR 01000 MAP
```

- `MAP` + `EXT` is a map where the schema is defined by pointing to a shared array.

```lua
[ { "a": 1, "b": 2 }, { "a": 3, "b": 4 } ] ->
[ "a", "b" ]->schema [ {schema 1, 2 }, {*schema 3, 4 } ] ->
  <62> STR(1) <61> STR(1) LST(2)
  NUM(8) NUM(6) MAP(2) EXT(3)
  NUM(4) NUM(1) MAP(2) EXT(7)
  LST(8) ->
    <62> 00001 STR <61> 00001 STR 00010 LST
    01000 NUM 00110 NUM 00010 MAP 00011 EXT
    00100 NUM 00010 NUM 00010 MAP 00111 EXT
    01000 LST
```

There are more `EXT` types reserved.  For `STR` + `EXT` might be a string chain (splitting up a string to deduplicate substrings.  `MAP` + `EXT` might be a map that points to an external schema.
