import { makeKey } from './structural-key.ts'

const NUM = 0 // 000
const EXT = 1 // 001
const STR = 2 // 010
const BIN = 3 // 011
const LST = 4 // 100
const MAP = 5 // 101
const PTR = 6 // 110
const REF = 7 // 111

// Encode arbitrary JSON serializable values into a compact binary format
// The format is written in reverse order with leaves and data first
// and headers and parents last.
//
// The core encoding technique is a reverse TLV format with 5 different bit-patterns
// for unsigned integers and 5 for signed integers.
//
// U5/Z5 supports 0 to 27 for unsigned and -14 to 13 for zigzag signed
//
//   ttt xxxxx (where xxxxx < 11100)
//
// U8/I8 supports 0 to 255 for unsigned or -128 to 127 for 2s complement signed
//
//   xxxxxxxx
//   ttt 11100
//
// U16/I16 supports 64Ki for unsigned or +- 32Ki for 2s complement signed
//
//   xxxxxxxx xxxxxxxx
//   ttt 11101
//
// U32/I32 supports 4Mi for unsigned or +- 2Mi for 2s complement signed
//
//   xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
//   ttt 11110
//
// U64/I64 supports 16Ei for unsigned or += 8Ei (I64) for 2s complement signed
//
//   xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
//   xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
//   ttt 11111
//
// There are 8 core value tags, each can be paired with any of the 10 varint encodings above
//
//   0 - EXT (data) - signed or unsigned depending on context
//   1 - NUM (value) - always signed
//   2 - STR (length) - always unsigned
//   3 - BIN (length) - always unsigned
//   4 - LST (length) - always unsigned
//   5 - MAP (length) - always unsigned
//   6 - PTR (offset) - always unsigned
//   7 - REF (index) - always unsigned
//
// The special EXT type is used to extend the core types with additional semantics and metadata.
//
//  NUM(base) + EXT(power) encodes decimal numbers as `base * 10 ^ power` (both signed)
//  MAP(length) + EXT(offset) combines a list of values with a pointer to a list of keys for typed maps.
//  STR(length) + EXT(count) lets you encode a string as a list of substrings (for deduplication)
//
// Built-in Refs
//
//   0 - null
//   1 - true
//   2 - false

export function encode(value: unknown): Uint8Array {
  const parts: Uint8Array[] = []
  let currentSize = 0
  // Map from value to byte offset it was written on
  const seen = new Map<unknown, number>()
  // Map from value to estimated cost of encoding it
  const costs = new Map<unknown, number>()

  encodeAny(value)

  const result = new Uint8Array(currentSize)
  let offset = 0
  for (const part of parts) {
    result.set(part, offset)
    offset += part.length
  }
  return result

  function writeUnsignedVarInt(type: number, value: number) {
    if (!Number.isInteger(value) || value < 0) {
      throw new Error(`Value is not a positive integer: ${value}`)
    }
    if (value < 28) {
      const part = new Uint8Array(1)
      part[0] = (type << 5) | value
      parts.push(part)
      currentSize += part.length
    } else if (value < 0x100) {
      const part = new Uint8Array(2)
      part[0] = value
      part[1] = (type << 5) | 0x1c
      parts.push(part)
      currentSize += part.length
    } else if (value < 0x10000) {
      const part = new Uint8Array(3)
      const view = new DataView(part.buffer)
      view.setUint16(0, value, true)
      part[2] = (type << 5) | 0x1d
      parts.push(part)
      currentSize += part.length
    } else if (value < 0x100000000) {
      const part = new Uint8Array(5)
      const view = new DataView(part.buffer)
      view.setUint32(0, value, true)
      part[4] = (type << 5) | 0x1e
      parts.push(part)
      currentSize += part.length
    } else {
      const part = new Uint8Array(9)
      const view = new DataView(part.buffer)
      view.setBigUint64(0, BigInt(value), true)
      part[8] = (type << 5) | 0x1f
      parts.push(part)
      currentSize += part.length
    }
  }

  function writeSignedVarInt(type: number, value: number | bigint) {
    if (typeof value === 'bigint') {
      const part = new Uint8Array(9)
      const view = new DataView(part.buffer)
      view.setBigInt64(0, value, true)
      part[8] = (type << 5) | 0x1f
      parts.push(part)
      currentSize += part.length
      return
    }
    if (!Number.isInteger(value)) {
      throw new Error(`Value is not an integer: ${value}`)
    }
    if (value >= -14 && value < 14) {
    // zigzag encode small values in single byte
      const zigzag = (value << 1) ^ (value >> 31)
      const part = new Uint8Array(1)
      part[0] = (type << 5) | zigzag
      parts.push(part)
      currentSize += part.length
    } else if (value >= -0x80 && value < 0x80) {
      // Encode using normal signed integers
      const part = new Uint8Array(2)
      part[0] = value & 0xff
      part[1] = (type << 5) | 0x1c
      parts.push(part)
      currentSize += part.length
    } else if (value >= -0x8000 && value < 0x8000) {
      const part = new Uint8Array(3)
      const view = new DataView(part.buffer)
      view.setInt16(0, value, true)
      part[2] = (type << 5) | 0x1d
      parts.push(part)
      currentSize += part.length
    } else if (value >= -0x80000000 && value < 0x80000000) {
      const part = new Uint8Array(5)
      const view = new DataView(part.buffer)
      view.setInt32(0, value, true)
      part[4] = (type << 5) | 0x1e
      parts.push(part)
      currentSize += part.length
    } else {
      const part = new Uint8Array(9)
      const view = new DataView(part.buffer)
      view.setBigInt64(0, BigInt(value), true)
      part[8] = (type << 5) | 0x1f
      parts.push(part)
      currentSize += part.length
    }
  }

  // Returns the offset of the written value (or offset of reused value)
  function encodeAny(val: unknown): number {
    const key = makeKey(val, 2)
    const seenOffset = seen.get(key)
    if (seenOffset !== undefined) {
      const estimatedCost = costs.get(key) || Infinity
      // If the cost of encoding this value is more than the cost of a pointer, use a pointer
      const delta = currentSize - seenOffset
      const estimatedPtrCost =
        delta < 28
          ? 1
          : delta < 0x100
            ? 2
            : delta < 0x10000
              ? 3
              : delta < 0x100000000
                ? 5
                : 9
      if (estimatedCost > estimatedPtrCost) {
        return encodePtr(seenOffset)
      }
    }
    const start = currentSize
    if (val == null) {
      encodeRef(0)
    } else if (val === true) {
      encodeRef(1)
    } else if (val === false) {
      encodeRef(2)
    } else if (typeof val === "number") {
      encodeNum(val)
    } else if (typeof val === "bigint") {
      encodeBigInt(val)
    } else if (typeof val === "string") {
      encodeStr(val)
    } else if (Array.isArray(val)) {
      encodeList(val)
    } else if (typeof val === "object") {
      if (ArrayBuffer.isView(val)) {
        encodeBin(new Uint8Array(val.buffer, val.byteOffset, val.byteLength))
      } else if (val instanceof ArrayBuffer) {
        encodeBin(new Uint8Array(val))
      } else {
        encodeMap(val as Record<string, unknown>)
      }
    } else {
      throw new Error(`Unsupported value: ${val}`)
    }
    seen.set(key, currentSize)
    costs.set(key, currentSize - start)
    return currentSize
  }

  function encodeRef(index: number) {
    return writeUnsignedVarInt(REF, index)
  }

  function encodePtr(offset: number) {
    writeUnsignedVarInt(PTR, currentSize - offset)
    return offset
  }

  function encodeNum(num: number) {
    const [base, power] = splitNumber(num)
    if (power < 0 || num >= 0x8000000000000000 || num < -0x8000000000000000) {
    // If the number has a decimal component or is too big, we have to encode it as a decimal
      encodeDecimal(base, power)
      return
    }
    const floatCost = signedVarIntSize(base) + signedVarIntSize(power)
    const intCost = signedVarIntSize(num)
    if (floatCost < intCost) {
      encodeDecimal(base, power)
    } else {
      encodeInteger(num)
    }
  }

  function encodeDecimal(base: number, power: number) {
    writeSignedVarInt(NUM, base)
    writeSignedVarInt(EXT, power)
  }

  function encodeInteger(num: number) {
    writeSignedVarInt(NUM, num)
  }

  function signedVarIntSize(value: number): number {
    if (value >= -14 && value < 14) {
      return 1
    } else if (value >= -0x80 && value < 0x80) {
      return 2
    } else if (value >= -0x8000 && value < 0x8000) {
      return 3
    } else if (value >= -0x80000000 && value < 0x80000000) {
      return 5
    } else {
      return 9
    }
  }

  function encodeBigInt(bi: bigint) {
    const num = Number(bi)
    if (BigInt(num) !== bi) {
      return writeSignedVarInt(NUM, bi)
    }
    return encodeNum(num)
  }

  function encodeStr(str: string) {
    if (str.length >= 28) {
      // Attempt to split longer strings to look for reuse
      const parts = str.match(/[^a-z0-9]*[a-z0-9 _-]*/gi)?.filter(Boolean)
      if (parts && parts.length > 1) {
        const start = currentSize
        for (let i = parts.length - 1; i >= 0; i--) {
          encodeAny(parts[i])
        }
        writeUnsignedVarInt(STR, parts.length)
        writeUnsignedVarInt(EXT, currentSize - start)
        return
      }
    }
    const utf8 = new TextEncoder().encode(str)
    parts.push(utf8)
    currentSize += utf8.length
    writeUnsignedVarInt(STR, utf8.length)
  }

  function encodeBin(bin: Uint8Array) {
    parts.push(bin)
    currentSize += bin.length
    writeUnsignedVarInt(BIN, bin.length)
  }

  function writeList(list: unknown[]) {
    // const offsets = new Uint8Array(list.length)
    for (let i = list.length - 1; i >= 0; i--) {
      encodeAny(list[i])
    }
    // parts.push(new Uint8Array(offsets.buffer))
    // currentSize += offsets.byteLength
  }

  function encodeList(list: unknown[]) {
    const start = currentSize
    writeList(list)
    writeUnsignedVarInt(LST, currentSize - start)
  }

  function encodeMap(map: Record<string, unknown> | Map<unknown, unknown>) {
    const start = currentSize
    const entries =
      map instanceof Map ? Array.from(map.entries()) : Object.entries(map)
    for (let i = entries.length - 1; i >= 0; i--) {
      const [key, entry] = entries[i]!
      encodeAny(entry)
      encodeAny(key)
    }
    // TODO: figure out how we want to do schema sharing
    // const entries = Object.entries(map).sort((a, b) =>
    // 	a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0,
    // );
    // const keys = entries.map((e) => e[0]);
    // const values = entries.map((e) => e[1]);
    // writeList(values);
    // // Encode keys as own sub-value so it can be deduplicated as a whole
    // encodeAny(keys);
    writeUnsignedVarInt(MAP, currentSize - start)
  }
}

// Input is an integer string.
// returns base and number of zeroes that were trimmed
function trimZeroes(str: string): [number, number] {
  const trimmed = str.replace(/0+$/, "")
  const zeroCount = str.length - trimmed.length
  return [parseInt(trimmed, 10), zeroCount]
}

// Given a double value, split it into a base and power of 10.
// For example, 1234.5678 would be split into 12345678 and -4.
export function splitNumber(val: number): [number, number] {
  if (Number.isInteger(val)) {
    if (Math.abs(val) < 10) {
      return [val, 0]
    }
    if (Math.abs(val) < 9.999999999999999e20) {
      return trimZeroes(val.toString())
    }
  }
  // Try decimal representation first
  const decStr = val.toPrecision(14).match(/^([-+]?\d+)(?:\.(\d+))?$/)
  if (decStr) {
    const b1 = parseInt((decStr[1] ?? "") + (decStr[2] ?? ""), 10)
    const e1 = -(decStr[2]?.length ?? 0)
    if (e1 === 0) {
      return [b1, 0]
    }
    const [b2, e2] = splitNumber(b1)
    return [b2, e1 + e2]
  }
  // Then try scientific notation
  const sciStr = val
    .toExponential(14)
    .match(/^([+-]?\d+)(?:\.(\d+))?(?:e([+-]?\d+))$/)
  if (sciStr) {
    // Count the decimal places
    const e1 = -(sciStr[2]?.length ?? 0)
    // Parse the exponent
    const e2 = parseInt(sciStr[3] ?? "0", 10)
    // Parse left of e as integer with zeroes trimmed
    const [b1, e3] = trimZeroes(sciStr[1] + (sciStr[2] ?? ""))
    return [b1, e1 + e2 + e3]
  }
  throw new Error(`Invalid number format: ${val}`)
}

export function decode(buffer: Uint8Array): unknown {

}
