# N₂: Data, Distilled

## Tagged Varint Encoding

The core encoding is the tagged varint that encodes a 3 bit type and up to 64 bit associated integer.

When integer is small, encode as a single byte.

```
ttt xxxxx (where xxxxx < 11100) 0 to 27 for unsigned and -14 to 13 for zigzag signed
```

The next 4 are fixed width encodings where the integer is encoded as `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, or `u64`.  All multi-byte values are little-endian to match WASM and modern computers.

```
xxxxxxxx 
ttt 11100 ( u8 / i8 ) 0 to 255 or -128 to 127 

xxxxxxxx xxxxxxxx 
ttt 11101 ( u16 /  i16 ) 64Ki or +- 32Ki

xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
ttt 11110 ( u32 / i32 ) 4Mi or +- 2Mi

xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
ttt 11111 ( u64 / i64 ) 16Ei or += 8Ei
```

## Value Types

N₂ has 8 different types that encodes nicely into 3 bits of information.

```
0 - EXT (data)
1 - NUM (value)
2 - STR (length)
3 - BIN (length)
4 - LST (length)
5 - MAP (length)
6 - PTR (offset)
7 - REF (index)
```

### NUM (signed int) - Integer

Simply encode any `i64` value with type tag `NUM` and the value as.

```js
function encodeInteger (num) {
  return encodeSignedPair(NUM, num)
}
```

### STR (len) - String

Strings are encoded by first writing the value using UTF-8 encoding.  This is followed by an unsigned tag pair with the byte length and type `STR`

```js
function encodeString(str) {
  const len = writeUtf8(str)
  return len + encodePair(STR, len)
}
```

### BIN (len) - Binary

Binary is the same as strings except it's already serialized to bytes

```js
function encodeBinary(bin) {
  const len = writeBinary(bin)
  return len + encodePair(BIN, len)
}
```

### LST (len) - List

Lists are encoded by first writing the items in reverse order followed by an unsigned tag pair for the total byte length of the children.

```js
function encodeList(lst) {
  let len = 0
  for (const val of reverseValues(lst)) {
    len += encodeAny(val)
  }
  return len + encodePair(LST, len)
}
```

### MAP (len) - Map

Maps are the same, except they key/value pairs are written (value first, then key since it's reverse)

```js
function encodeMap(map) {
  let len = 0
  for (const [key, value] of reverseEntries(map)) {
    len += encodeAny(val)
    len += encodeAny(key)
  }
  return len + encodePair(MAP, len)
}
```

### PTR (offset) - Pointer

Pointers are simply byte offsets to other values, they are encoded as unsigned integer offsets (calculated before writing value)

```js
function encodePointer(target) {
  const delta = current - target
  return encodePair(PTR, delta)
}
```

### REF (index) - Reference

The first values in the shared dictionary are `null`, `true`, and `false`.  Users of the format can extend this as long as both the encoder and decoder agree on what the other values are.

```js
// The default refs map
const refs = new Map([
  [null, 0],
  [true, 1],
  [false, 2],
])
```

This will be checked at the top of `encodeAny` so that refs supersede other encoders.

```js
function encodeAny(val) {
  if (refs.has(val)) {
    return encodePair(REF, refs.get(val))
  }
  ...
}
```

### EXT ... - Extensions

Many of the types have advanced versions where two pairs are used for the encoding.

#### EXT (signed pow) NUM (base) - Decimal

For decimal, split the value into an integer base and a power of 10.  Encode the base first as `NUM`, then encode the power as `EXT`

```js
function encodeDecimal(num, pow) {
  const len = encodeSignedPair(NUM, num)
  return len + encodeSignedPair(EXT, pow)
}
```

#### EXT (count) STR (len) - String Chain

Advanced encoders may wish to deduplicate common substrings, the string chain allows n values to be combined into a single string.  You can mix strings and refs to string (and recursive string chains)

```js
function encodeStrings(vals) {
  let len = 0
  let count = 0
  for (const val of reverse(vals)) {
    len += encodeAny(val)
    count++
  }
  len += encodePair(STR, len)
  return len + encodePair(EXT, count)
}
```

#### EXT (count) BIN (len) - Bin Chain

This is the same idea except the parts are written as strings, binary, refs, string chains, bin chains.

```js
function encodeBins(vals) {
  let len = 0
  let count = 0
  for (const val of reverse(vals)) {
    len += encodeAny(val)
    count++
  }
  len += encodePair(BIN, len)
  return len + encodePair(EXT, count)
}
```

#### EXT (count) LST (width) - Array

When `EXT` is followed by `LST`, the first signed integer is the pointer width and the second unsigned integer is the item count.

The body of this is an array of fixed-width offset pointers. (offsets recorded before writing array)

```js
function encodeArray(arr) {
  const offsets = []
  const start = current
  let count = 0
  for (const val of arr) {
    if (seen.has(val)) {
      offsets[count++] = seen.get(val)
    } else {
      offsets[count++] = encodeAny(val)
    }
  }
  let maxDelta = 0
  for (const offset of offsets) {
    maxDelta = Math.max(maxDelta, start - offset)
  }
  const bitsNeeded = Math.floor(Math.log2(maxDelta)) + 1
  const width = Math.ceil(bitsNeeded / 8)
  let len = count * width
  for (let i = count - 1; i >= 0; i--) {
    encodePointer(width, start - offsets[i])
  }
  len += encodePair(MAP, count)
  return len + encodePair(EXT, width)

}
```

#### EXT (count) MAP (width) - Binary Tree

When `EXT` is followed by `MAP`, the first signed integer is the pointer width and the second unsigned integer is the item count.

The body is an array of fixed-width offset pointers to the keys (the values are always behind the keys).

The index entries are sorted in eytzinger layout so that a fast binary search can be performed.

_**TODO**: define sorting order._


#### EXT PTR - ???

_Reserved for future use._

#### EXT REF - ???

_Reserved for future use._

#### EXT EXT ... - ???

_Reserved for future use._

## Samples

### Encode Short String

Encode the string `"Hello World"`

First write the string contents with UTF-8 encoding. `<48656c6c6f20576f726c64>`

We now need to write the type and length.  Since this string was 11 bytes, it fits in the small size (0-27).

- `xxxxx` -> 11 -> `01011`
- `ttt` -> 2 -> `010`

Combined the byte is `01011010` which is `<5a>`.

The final encoding is `<48656c6c6f20576f726c64 5a>`

### Encode Small Integer

Small integers (-14 to 13 range) are encoded