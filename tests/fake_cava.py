#!/usr/bin/python3
"""Stands in for cava in tests: ignores its arguments and prints 20 known
bar levels 30 times per second, like cava's raw ascii output."""
import sys
import time

LINE = ";".join(str(5 * i) for i in range(20)) + ";\n"
while True:
    sys.stdout.write(LINE)
    sys.stdout.flush()
    time.sleep(1 / 30)
