import { encode, splitNumber, decode } from "./n2.ts";
import { parse } from "./json-with-binary.ts";
import { expect, test } from "bun:test";

function toHex(buf: Uint8Array) {
  return Array.from(buf)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}

// Remove whitespace from a hex string for easier comparison
// Also strip comments
function stripJoin(...hex: string[]) {
  return hex.join("").replace(/\s+/g, "")
}

test("splitting numbers", () => {
  expect(splitNumber(0)).toEqual([0, 0])
  expect(splitNumber(1)).toEqual([1, 0])
  expect(splitNumber(10)).toEqual([1, 1])
  expect(splitNumber(1e5)).toEqual([1, 5])
  expect(splitNumber(1e20)).toEqual([1, 20])
  expect(splitNumber(1.5e20)).toEqual([15, 19])
  expect(splitNumber(1.2345e-10)).toEqual([12345, -14])
  expect(splitNumber(-1.2345e-10)).toEqual([-12345, -14])
  expect(splitNumber(1.2345e10)).toEqual([12345, 6])
  expect(splitNumber(Math.PI)).toEqual([31415926535898, -13]);

  for (let i = -200; i <= 200; i++) {
    expect(splitNumber(0)).toEqual([0, 0])
    expect(splitNumber(10 ** i)).toEqual([1, i])
    expect(splitNumber(314 * 10 ** i)).toEqual([314, i])
    expect(splitNumber(12345678912345 * 10 ** i)).toEqual([12345678912345, i])
  }
});

test("Encodes primitive values", () => {
  // Primitives using REF
  expect(toHex(encode(null))).toEqual("e0")
  expect(toHex(encode(true))).toEqual("e1")
  expect(toHex(encode(false))).toEqual("e2")
});

test("Encodes integers", () => {
  // Small Signed Integers
  expect(toHex(encode(0))).toEqual("00")
  expect(toHex(encode(-1))).toEqual("01")
  expect(toHex(encode(1))).toEqual("02")
  expect(toHex(encode(-2))).toEqual("03")
  expect(toHex(encode(2))).toEqual("04")
  expect(toHex(encode(-13))).toEqual("19")
  expect(toHex(encode(13))).toEqual("1a")
  expect(toHex(encode(-14))).toEqual("1b")
  // I8 Integers
  expect(toHex(encode(15))).toEqual("0f1c")
  expect(toHex(encode(-15))).toEqual("f11c")
  expect(toHex(encode(100))).toEqual("641c")
  expect(toHex(encode(-100))).toEqual("9c1c")
  // I16 Integers
  expect(toHex(encode(256))).toEqual("00011d")
  expect(toHex(encode(-256))).toEqual("00ff1d")
  expect(toHex(encode(1001))).toEqual("e9031d")
  expect(toHex(encode(-1001))).toEqual("17fc1d")
  // I32 Integers
  expect(toHex(encode(65536))).toEqual("000001001e")
  expect(toHex(encode(-65536))).toEqual("0000ffff1e")
  expect(toHex(encode(16777216))).toEqual("000000011e")
  expect(toHex(encode(-16777216))).toEqual("000000ff1e")
  expect(toHex(encode(-70001))).toEqual("8feefeff1e")
  expect(toHex(encode(5_000_001))).toEqual("414b4c001e")
  expect(toHex(encode(-5_000_001))).toEqual("bfb4b3ff1e")
  // I64 Integers
  expect(toHex(encode(4294967296))).toEqual("00000000010000001f")
  expect(toHex(encode(-4294967296))).toEqual("00000000ffffffff1f")
  // BigInt within i53 range
  expect(toHex(encode(0xdeadbeefn))).toEqual("efbeadde000000001f")
  expect(toHex(encode(-0xdeadbeefn))).toEqual("11415221ffffffff1f")
  // BigInt within i64 range
  expect(toHex(encode(0x123456789abcdefn))).toEqual("efcdab89674523011f")
  expect(toHex(encode(-0x123456789abcdefn))).toEqual("1132547698badcfe1f")
});

test("Encodes strings", () => {
  expect(toHex(encode(""))).toEqual("40")
  expect(toHex(encode("a"))).toEqual("6141")
  expect(toHex(encode("abc"))).toEqual("61626343")
  expect(toHex(encode("Hello, World!"))).toEqual(
    "48656c6c6f2c20576f726c64214d",
  )
  expect(
    toHex(encode("This is a longer string that exceeds 27 characters.")),
  ).toEqual(
    "2e41546869732069732061206c6f6e67657220737472696e67207468617420657863656564732032372063686172616374657273325c365c22",
  )
  expect(toHex(encode("😀"))).toEqual("f09f988044")
});

test("Encodes binary data", () => {
  expect(toHex(encode(new Uint8Array([])))).toEqual("60")
  expect(toHex(encode(new Uint8Array([0])))).toEqual("0061")
  expect(toHex(encode(new Uint8Array([1, 2, 3, 4, 5])))).toEqual(
    "010203040565",
  )
  expect(toHex(encode(new Uint8Array([...Array(30).keys()])))).toEqual(
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e7c",
  )
});

test("Encodes arrays", () => {
  expect(toHex(encode([]))).toEqual("80")
  expect(toHex(encode([1, 2, 3]))).toEqual("06040283")
  expect(toHex(encode([null, true, false]))).toEqual("e2e1e083")
  expect(toHex(encode([1, [2, [3]]]))).toEqual("068104830285")
  expect(toHex(encode(new Array(30).fill(0).map((_, i) => i)))).toEqual(
    "1d1c1c1c1b1c1a1c191c181c171c161c151c141c131c121c111c101c0f1c0e1c1a18161412100e0c0a08060402002e9c",
  )
});

test("Encodes objects", () => {
  expect(toHex(encode({}))).toEqual("a0")
  expect(toHex(encode({ a: 1, b: 2 }))).toEqual("046241026141a6")
  expect(toHex(encode({ foo: "bar", baz: [1, 2, 3] }))).toEqual(
    "0604028362617a4362617243666f6f43b0",
  )
  expect(toHex(encode({ nested: { a: { b: { c: 3 } } } }))).toEqual(
    "066341a36241a66141a96e657374656446b1",
  )
  expect(toHex(encode({ a: 1, b: { c: 2, d: [3, 4] }, e: "five" }))).toEqual(
    "666976654465410806826441046341a86241026141b5",
  )
});

test("Encodes with references", () => {
  expect(toHex(encode(["repeat", "repeat", "repeat"]))).toEqual(
    "72657065617446c0c189",
  )
  expect(toHex(encode({ a: "same", b: "same", c: "same" }))).toEqual(
    "73616d65446341c26241c56141ad",
  )
  const obj = { key: "value" }
  expect(toHex(encode(obj))).toEqual("76616c7565456b657943aa")
  expect(toHex(encode([obj, obj, obj]))).toEqual("76616c7565456b657943aac0c18d")
});

test("Encodes with shared schemas", () => {
  const data = [
    { a: 1, b: 2 },
    { a: 3, b: 4 },
    { a: 5, b: 6 },
    { a: 7, b: 8 },
  ]
  expect(toHex(encode(Object.keys(data[0])))).toEqual(
    stripJoin(
      "  6241", // "b"
      "  6141", // "a"
      "84",     // array with 4 bytes
    ),
  )
  expect(toHex(encode(data[0]))).toEqual(
    stripJoin(
      "  04",   // 2
      "  6241", // "b"
      "  02",   // 1
      "  6141", // "a"
      "a6",     // object with 6 bytes
    ),
  )
  expect(
    toHex(
      encode(data.slice(0, 2)),
    ),
  ).toEqual(
    stripJoin(
      "  62 41", // "b"
      "  61 41", // "a"
      "84",      // array with 4 bytes"

      "  08",  // 4
      "  06",  // 3
      "a7 23", // object with 2 bytes and pointer back 3 to schema

      "  04",  // 2
      "  02",  // 1
      "a2 27", // object with 2 bytes and pointer back 8 to schema

      "8d", // array with 13 bytes
    ),
  )
  expect(toHex(encode(data))).toEqual(
    stripJoin(
      "  6241", // "b"
      "  6141", // "a"
      "84",     // array with 4 bytes

      "  10",  // 8
      "  0e",  // 7
      "a7 23", // object with 2 bytes and pointer back 3 to schema

      "  0c",  // 6
      "  0a",  // 5
      "a2 27", // object with 2 bytes and pointer back 7 to schema

      "  08",  // 4
      "  06",  // 3
      "a2 2b", // object with 2 bytes and pointer back 11 to schema

      "  04",  // 2
      "  02",  // 1
      "a2 2f", // object with 2 bytes and pointer back 15 to schema

      "95", // array with 21 bytes
    ),

  )
});

test('Encodes string splitting correctly', () => {
  const paths = [
    "/section/first/chapter/second/where-the-wild-things|are",
    "/section/first/chapter/second/where-the-wild-things|were",
    "/section/first/chapter/second/where-the-wild-things|will-be",
  ]
  const encoded = encode(paths)
  expect(toHex(encoded)).toEqual(stripJoin(

    "  7c77696c6c2d626548", // "|will-be"
    "  2f77686572652d7468652d77696c642d7468696e677356", // "/where-the-wild-things"
    "  2f7365636f6e6447",   // "/second"
    "  2f6368617074657248", // "/chapter"
    "  2f666972737446",     // "/first"
    "  2f73656374696f6e48", // "/section"
    "415c 26",              // STR(size 69) EXT(count 6)

    "  7c7765726545", // "|were"
    "  2adc",         // Pointer 42 back to previous "/where-the-wild-things"
    "  24dc",         // Pointer 36 back to previous "/second"
    "  1ddc",         // Pointer 29 back to previous "/chapter"
    "  d8",           // Pointer 24 back to previous "/first"
    "  d0",           // Pointer 16 back to previous "/section"
    "4e 26",          // STR(size 14) EXT(count 6)

    "  7c61726544", // "|are"
    "  39dc",       // Pointer 57 back to previous "/where-the-wild-things"
    "  33dc",       // Pointer 51 back to previous "/second"
    "  2cdc",       // Pointer 44 back to previous "/chapter"
    "  27dc",       // Pointer 39 back to previous "/first"
    "  20dc",       // Pointer 32 back to previous "/section"
    "4f 26",        // STR(size 15) EXT(count 6)

    "659c" // ARR(size 101)
  ))
})

test("Encodes the same as the fixtures file", async () => {
  const fixture: Map<string, unknown[]> = parse(
    await Bun.file("../fixtures/encode.tibs").text(),
    "../fixtures/encode.tibs",
  )
  for (const [section, tests] of fixture.entries()) {
    for (let i = 0, l = tests.length; i < l; i += 2) {
      const input = tests[i]
      const expected = toHex(tests[i + 1] as Uint8Array)
      const actual = toHex(encode(input))
      if (actual !== expected) {
        console.error({ section, input, expected, actual__: actual })
        throw new Error(`Mismatch in ${section}[${i / 2}]`)
      }
    }
  }
});
