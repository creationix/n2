import { encode, splitNumber, decode } from "./n2.ts";
import { parse } from "./json-with-binary.ts";
import { expect, test } from "bun:test";

function toHex(buf: Uint8Array) {
	return Array.from(buf)
		.map((b) => b.toString(16).padStart(2, "0"))
		.join("");
}

// Remove whitespace from a hex string for easier comparison
// Also strip comments
function stripJoin(...hex: string[]) {
	return hex.join("").replace(/\s+/g, "");
}

test.only("splitting numbers", () => {
	expect(splitNumber(0)).toEqual([0, 0]);
	expect(splitNumber(1)).toEqual([1, 0]);
	expect(splitNumber(10)).toEqual([1, 1]);
	expect(splitNumber(1e5)).toEqual([1, 5]);
	expect(splitNumber(1e20)).toEqual([1, 20]);
	expect(splitNumber(1.5e20)).toEqual([15, 19]);
	expect(splitNumber(1.2345e-10)).toEqual([12345, -14]);
	expect(splitNumber(-1.2345e-10)).toEqual([-12345, -14]);
	expect(splitNumber(1.2345e10)).toEqual([12345, 6]);

	for (let i = -200; i <= 200; i++) {
		let [base, exponent] = splitNumber(0);
		expect([base, exponent]).toEqual([0, 0]);
		[base, exponent] = splitNumber(10 ** i);
		expect([base, exponent]).toEqual([1, i]);
		[base, exponent] = splitNumber(314 * 10 ** i);
		expect([base, exponent]).toEqual([314, i]);
		[base, exponent] = splitNumber(12345678912345 * 10 ** i);
		expect([base, exponent]).toEqual([12345678912345, i]);
	}
});

test("Encodes primitive values", () => {
	// Primitives using REF
	expect(toHex(encode(null))).toEqual("e0");
	expect(toHex(encode(true))).toEqual("e1");
	expect(toHex(encode(false))).toEqual("e2");
});

test("Encodes integers", () => {
	// Small Signed Integers
	expect(toHex(encode(0))).toEqual("20");
	expect(toHex(encode(-1))).toEqual("21");
	expect(toHex(encode(1))).toEqual("22");
	expect(toHex(encode(-2))).toEqual("23");
	expect(toHex(encode(2))).toEqual("24");
	expect(toHex(encode(-13))).toEqual("39");
	expect(toHex(encode(13))).toEqual("3a");
	expect(toHex(encode(-14))).toEqual("3b");
	// I8 Integers
	expect(toHex(encode(15))).toEqual("0f3c");
	expect(toHex(encode(-15))).toEqual("f13c");
	expect(toHex(encode(100))).toEqual("643c");
	expect(toHex(encode(-100))).toEqual("9c3c");
	// I16 Integers
	expect(toHex(encode(256))).toEqual("00013d");
	expect(toHex(encode(-256))).toEqual("00ff3d");
	expect(toHex(encode(1000))).toEqual("e8033d");
	expect(toHex(encode(-1000))).toEqual("18fc3d");
	// I32 Integers
	expect(toHex(encode(65536))).toEqual("000001003e");
	expect(toHex(encode(-65536))).toEqual("0000ffff3e");
	expect(toHex(encode(16777216))).toEqual("000000013e");
	expect(toHex(encode(-16777216))).toEqual("000000ff3e");
	expect(toHex(encode(-70000))).toEqual("90eefeff3e");
	expect(toHex(encode(5_000_000))).toEqual("404b4c003e");
	expect(toHex(encode(-5_000_000))).toEqual("c0b4b3ff3e");
	// I64 Integers
	expect(toHex(encode(4294967296))).toEqual("00000000010000003f");
	expect(toHex(encode(-4294967296))).toEqual("00000000ffffffff3f");
	// BigInt within i53 range
	expect(toHex(encode(0xdeadbeefn))).toEqual("efbeadde000000003f");
	expect(toHex(encode(-0xdeadbeefn))).toEqual("11415221ffffffff3f");
	// BigInt within i64 range
	expect(toHex(encode(0x123456789abcdefn))).toEqual("efcdab89674523013f");
	expect(toHex(encode(-0x123456789abcdefn))).toEqual("1132547698badcfe3f");
});

test("Encodes strings", () => {
	expect(toHex(encode(""))).toEqual("40");
	expect(toHex(encode("a"))).toEqual("6141");
	expect(toHex(encode("abc"))).toEqual("61626343");
	expect(toHex(encode("Hello, World!"))).toEqual(
		"48656c6c6f2c20576f726c64214d",
	);
	expect(
		toHex(encode("This is a longer string that exceeds 27 characters.")),
	).toEqual(
		"2e41546869732069732061206c6f6e67657220737472696e67207468617420657863656564732032372063686172616374657273325c42371c",
	);
	expect(toHex(encode("😀"))).toEqual("f09f988044");
});

test("Encodes binary data", () => {
	expect(toHex(encode(new Uint8Array([])))).toEqual("60");
	expect(toHex(encode(new Uint8Array([0])))).toEqual("0061");
	expect(toHex(encode(new Uint8Array([1, 2, 3, 4, 5])))).toEqual(
		"010203040565",
	);
	expect(toHex(encode(new Uint8Array([...Array(30).keys()])))).toEqual(
		"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e7c",
	);
});

test("Encodes arrays", () => {
	expect(toHex(encode([]))).toEqual("80");
	expect(toHex(encode([1, 2, 3]))).toEqual("26242283");
	expect(toHex(encode([null, true, false]))).toEqual("e2e1e083");
	expect(toHex(encode([1, [2, [3]]]))).toEqual("268124832285");
	expect(toHex(encode(new Array(30).fill(0).map((_, i) => i)))).toEqual(
		"1d3c1c3c1b3c1a3c193c183c173c163c153c143c133c123c113c103c0f3c0e3c3a38363432302e2c2a28262422202e9c",
	);
});

test("Encodes objects", () => {
	expect(toHex(encode({}))).toEqual("80a1");
	expect(toHex(encode({ a: 1, b: 2 }))).toEqual("24226241614184a7");
	expect(toHex(encode({ foo: "bar", baz: [1, 2, 3] }))).toEqual(
		"6261724326242283666f6f4362617a4388b1",
	);
	expect(toHex(encode({ nested: { a: { b: { c: 3 } } } }))).toEqual(
		"26634182a4624182a8614182ac6e65737465644687b5",
	);
	expect(toHex(encode({ a: 1, b: { c: 2, d: [3, 4] }, e: "five" }))).toEqual(
		"6669766544282682246441634184a92265416241614186b7",
	);
});

test("Encodes with references", () => {
	expect(toHex(encode(["repeat", "repeat", "repeat"]))).toEqual(
		"72657065617446c0c189",
	);
	expect(toHex(encode({ a: "same", b: "same", c: "same" }))).toEqual(
		"73616d6544c0c163416241614186ae",
	);
	const obj = { key: "value" };
	expect(toHex(encode(obj))).toEqual("76616c7565456b65794384ab");
	expect(toHex(encode([obj, obj, obj]))).toEqual(
		"76616c7565456b65794384abc0c18e",
	);
});

test("Encodes with shared schemas", () => {
	const data = [
		{ a: 1, b: 2 },
		{ a: 3, b: 4 },
		{ a: 5, b: 6 },
		{ a: 7, b: 8 },
	];
	const keys = Object.keys(data[0]);
	expect(toHex(encode(keys))).toEqual(
		stripJoin(
			"62 41", // "b"
			"61 41", // "a"
			"  84", // array with 4 bytes
		),
	);
	expect(toHex(encode({ a: 1, b: 2 }))).toEqual(
		stripJoin(
			"24", // 2
			"22", // 1
			"62 41", // "b"
			"61 41", // "a"
			"  84", // array with 4 bytes
			"    a7", // object with 7 bytes
		),
	);
	expect(
		toHex(
			encode([
				{ a: 1, b: 2 },
				{ a: 3, b: 4 },
			]),
		),
	).toEqual(
		stripJoin(
			"28", // 4
			"26", // 3
			"62 41", // "b"
			"61 41", // "a"
			"  84", // array with 4 bytes
			"    a7", // object with 7 bytes
			"24", // 2
			"22", // 1
			"  c3", // Pointer to schema 3 bytes back
			"    a3", // object with 3 bytes
			"      8c", // array with 12 bytes
		),
	);
	expect(toHex(encode(data))).toEqual(
		stripJoin(
			"30", // 8
			"2e", // 7
			"62 41", // "b"
			"61 41", // "a"
			"  84", // array with 4 bytes
			"    a7", // object with 7 bytes
			"2c", // 6
			"2a", // 5
			"  c3", // pointer back 3 bytes to schema
			"    a3", // object with 3 bytes
			"28", // 4
			"26", // 3
			"  c7", // pointer back 7 bytes to schema
			"    a3", // object with 3 bytes
			"24", // 2
			"22", // 1
			"  cb", // pointer back 11 bytes to schema
			"    a3", // object with 3 bytes
			"      94", // array with 20 bytes
		),
	);
});

test("Encodes the same as the fixtures file", async () => {
	const fixture: Map<string, unknown[]> = parse(
		await Bun.file("fixtures/encode.tibs").text(),
		"fixtures/encode.tibs",
	);
	console.log({ fixture });
	for (const [section, tests] of fixture.entries()) {
		for (let i = 0, l = tests.length; i < l; i += 2) {
			const input = tests[i];
			const expected = toHex(tests[i + 1] as Uint8Array);
			const actual = toHex(encode(input));
			if (actual !== expected) {
				console.error({ section, input, expected, actual });
				throw new Error(`Mismatch in ${section}[${i / 2}]`);
			}
		}
	}
});
