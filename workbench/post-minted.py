#!/usr/bin/env python3
import fileinput
import sys

if len(sys.argv) < 4:
  raise ValueError(f'Need three args at least, given {len(sys.argv)}')

fin = sys.argv[1]
wrapper = sys.argv[2]
print(f'File: {fin}')
with fileinput.input(fin, inplace=True) as file:
  for cmd in sys.argv[3:]:
    pattern_find = fR'{{\PYGZbs{{}}{cmd}}}'
    pattern_sub = fR'{{\{wrapper}{{\PYGZbs{{}}{cmd}}}}}'
    for line in file:
      print(line.replace(pattern_find, pattern_sub), end='')
