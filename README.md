```
types:
0 - integers (signed value)
1 - decimals (signed power, signed base)
2 - strings (unsigned length)
3 - binary (unsigned length)
4 - lists (unsigned length)
5 - maps (unsigned length)
6 - pointers (unsigned offset)
7 - refs (unsigned index)

builtin refs:
0 - null
1 - true
2 - false

tagged varint:
ttt xxxxx ( u5 / zigzag(u5) ) 0 to 27 or -14 to 13
ttt 11100 xxxxxxxx ( u8 / i8 ) 0 to 255 or -128 to 127
ttt 11101 xxxxxxxx xxxxxxxx ( u16-le /  i16-le ) 64Ki or +- 32Ki
ttt 11110 xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx ( u32-le / i32-le ) 4Mi or +- 2Mi
ttt 11111 xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
          xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx ( u64-l2 / i64-le ) 16Ei or += 8Ei
...

untagged varint:
xxxxxxxx (u8 / zigzag(u8) ) 0 to 251 or -126 to 125
11111100 xxxxxxxx ( u8 / i8 ) 0 to 255 or -128 to 127
11111101 xxxxxxxx xxxxxxxx ( u16-le /  i16-le ) 64Ki or +- 32Ki
11111110 xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx ( u32-le, i32-le ) 4Mi or +- 2Mi
11111111 xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
         xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx ( u64-le, i64-le ) 16Ei or += 8Ei
... 
```