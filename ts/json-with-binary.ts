// JSON-With-Binary is an extension of JSON that allows binary data
// to be stored alongside JSON data.
// The syntax for binary data is `<` hex-encoded-bytes `>`
// For example: `{ "image": <89504E470D0A1A0A0000000D49484452> }`
// The hex bytes are allowed to have whitespace (including newlines and comments)
// This format also allows some laxness in JSON itself:
// - single quoted strings: `{ 'key': 'value' }`
// - any value as keys: `{ 123: 'value', true: 'value', null: 'value' }`
// - trailing commas: `{ 'key': 'value', }`
// - JS comments: `// comment` and `/* comment */`

export function parse(input: string, filename = "[memory]"): any {
  let index = 0
  const length = input.length

  function isWhitespace(char: string): boolean {
    return /\s/.test(char)
  }

  function isHexDigit(char: string): boolean {
    return /[0-9a-fA-F]/.test(char)
  }

  function skipWhitespaceAndComments() {
    while (index < length) {
      const char = input[index]
      if (char === undefined) break
      if (isWhitespace(char)) {
        index++
      } else if (char === "/" && input[index + 1] === "/") {
        // Single line comment
        index += 2
        while (index < length && input[index] !== "\n") {
          index++
        }
      } else if (char === "/" && input[index + 1] === "*") {
        // Multi-line comment
        index += 2
        while (
          index < length &&
          !(input[index] === "*" && input[index + 1] === "/")
        ) {
          index++
        }
        index += 2 // Skip closing */
      } else {
        break
      }
    }
  }

  function parseValue(): any {
    skipWhitespaceAndComments()
    const char = input[index] as string
    if (char === "{") {
      return parseMap()
    } else if (char === "[") {
      return parseArray()
    } else if (char === '"' || char === "'") {
      return parseString()
    } else if (char === "<") {
      return parseBinary()
    } else if (/[0-9-]/.test(char)) {
      return parseNumber()
    } else if (input.startsWith("true", index)) {
      index += 4
      return true
    } else if (input.startsWith("false", index)) {
      index += 5
      return false
    } else if (input.startsWith("null", index)) {
      index += 4
      return null
    } else {
      throw new SyntaxError(`Unexpected token ${char} at position ${index}`)
    }
  }

  function parseMap(): any {
    const map = new Map<any, any>()
    index++ // Skip '{'
    skipWhitespaceAndComments()
    while (index < length && input[index] !== "}") {
      const key = parseValue()
      skipWhitespaceAndComments()
      if (input[index] !== ":") {
        throw new SyntaxError(`Expected ':' after key at position ${index}`)
      }
      index++ // Skip ':'
      const value = parseValue()
      map.set(key, value)
      skipWhitespaceAndComments()
      if (input[index] === ",") {
        index++ // Skip ','
        skipWhitespaceAndComments()
      } else {
        break
      }
    }
    if (input[index] !== "}") {
      throw new SyntaxError(`Expected '}' at position ${index}`)
    }
    index++ // Skip '}'
    return map
  }

  function parseArray(): any[] {
    const arr: any[] = []
    index++ // Skip '['
    skipWhitespaceAndComments()
    while (index < length && input[index] !== "]") {
      const value = parseValue()
      arr.push(value)
      skipWhitespaceAndComments()
      if (input[index] === ",") {
        index++ // Skip ','
        skipWhitespaceAndComments()
      } else {
        break
      }
    }
    if (input[index] !== "]") {
      throw new SyntaxError(
        `Expected ']' at position ${toLocation(index, input, filename)}`,
      )
    }
    index++ // Skip ']'
    return arr
  }

  function parseString(): string {
    const quoteType = input[index]
    let str = ""
    index++ // Skip opening quote
    while (index < length) {
      const char = input[index]
      if (char === quoteType) {
        index++ // Skip closing quote
        return str
      } else if (char === "\\") {
        index++
        const escapeChar = input[index]
        if (escapeChar === "n") str += "\n"
        else if (escapeChar === "r") str += "\r"
        else if (escapeChar === "t") str += "\t"
        else if (escapeChar === "b") str += "\b"
        else if (escapeChar === "f") str += "\f"
        else if (escapeChar === "u") {
          const hex = input.substr(index + 1, 4)
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
            throw new SyntaxError(
              `Invalid Unicode escape sequence at position ${index}`,
            )
          }
          str += String.fromCharCode(parseInt(hex, 16))
          index += 4
        } else {
          str += escapeChar
        }
      } else {
        str += char
      }
      index++
    }
    throw new SyntaxError(`Unterminated string at position ${index}`)
  }

  function parseBinary(): Uint8Array {
    index++ // Skip '<'
    let hexString = ""
    while (index < length) {
      skipWhitespaceAndComments()
      const char = input[index]
      if (char === undefined) break
      if (char === ">") {
        index++ // Skip '>'
        break
      } else if (isHexDigit(char)) {
        hexString += char
      } else {
        throw new SyntaxError(
          `Invalid character in binary data at position ${index}`,
        )
      }
      index++
    }
    if (hexString.length % 2 !== 0) {
      throw new SyntaxError(
        `Hex string must have an even length at position ${index}`,
      )
    }
    const byteLength = hexString.length / 2
    const byteArray = new Uint8Array(byteLength)
    for (let i = 0; i < byteLength; i++) {
      byteArray[i] = parseInt(hexString.substring(i * 2, (i + 1) * 2), 16)
    }
    return byteArray
  }

  function parseNumber(): number | bigint {
    let numStr = ""
    while (index < length) {
      const char = input[index]
      if (/[0-9eE\+\-\.]/.test(char)) {
        numStr += char
        index++
      } else {
        break
      }
    }
    let num: bigint | number = Number(numStr)
    try {
      num = BigInt(numStr)
      if (Number.MAX_SAFE_INTEGER >= num && num >= Number.MIN_SAFE_INTEGER) {
        num = Number(num)
      }
    } catch {
      if (!Number.isFinite(num)) {
        throw new SyntaxError(`Invalid number at position ${index}`)
      }
    }
    return num
  }

  const result = parseValue()
  skipWhitespaceAndComments()
  if (index < length) {
    throw new SyntaxError(`Unexpected token at position ${index}`)
  }
  return result
}

// Given an index in the input, return a string with line and column information.
function toLocation(index: number, input: string, filename: string): string {
  const lines = input.slice(0, index).split("\n")
  const line = lines.length
  const column = (lines.pop()?.length ?? 0) + 1
  return `${filename}:${line}:${column}`
}
