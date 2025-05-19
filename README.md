## Types

```
0 - integers (zigzag-value)
1 - decimals (zigzag-power, zigzag-base)
2 - strings (length)
3 - binary (length)
4 - lists (length)
5 - maps (length)
6 - pointers (offset)
7 - refs (index)

builtin refs:
0 - null
1 - true
2 - false


The first varint shares 3 bits for type

ttt 0xxxx (0-15)
ttt 1xxxx 0xxxxxxx
ttt 1xxxx 1xxxxxxx 0xxxxxxx
...

The second varint (used only by decimals) start with all 8 bits

0xxxxxxx
1xxxxxxx 0xxxxxxx
1xxxxxxx 1xxxxxxx 0xxxxxxx
...
```