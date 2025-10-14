// Create a unique key for any JSON serializable value
// For non-deeply nested objects this will match on the same structure
// For deeply nested objects this may produce different keys for the same structure
export function makeKey(val: unknown, depth = 1): unknown {
  if (depth <= 0) return val
  if (typeof val === 'string') return `'${val}'`
  if (!val || typeof val !== 'object') {
    return String(val)
  }
  if (Array.isArray(val)) {
    const parts: string[] = []
    for (const item of val) {
      const childKey = makeKey(item, depth - 1)
      if (typeof childKey !== 'string') return val
      parts.push(childKey)
    }
    return `[${parts.join(',')}]`
  }
  const parts: string[] = []
  for (const [key, value] of Object.entries(val as Record<string, unknown>)) {
    const childKey = makeKey(value, depth - 1)
    if (typeof childKey !== 'string') return val
    parts.push(`${key}:${childKey}`)
  }
  return `{${parts.join(',')}}`
}
