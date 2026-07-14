"""Strip all VHDL comments from the given files, in place.

Removes '--' comments (respecting double-quoted string literals), drops
full-line comments, trims trailing whitespace, collapses consecutive blank
lines to a single blank line, and removes leading blank lines. Preserves the
file's original newline style and writes BOM-free UTF-8.
"""
import sys


def strip_comment(line: str) -> str:
    in_str = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '"':
            in_str = not in_str
        elif ch == '-' and not in_str and i + 1 < len(line) and line[i + 1] == '-':
            return line[:i]
        i += 1
    return line


def process(text: str) -> str:
    out = []
    blank_run = 0
    started = False
    for line in text.split('\n'):
        code = strip_comment(line).rstrip()
        if code == '':
            # Was the original line non-blank (i.e. a pure comment)? Either way
            # collapse to a single blank line and never emit leading blanks.
            if not started:
                continue
            blank_run += 1
            continue
        if blank_run:
            out.append('')
            blank_run = 0
        out.append(code)
        started = True
    return '\n'.join(out)


def main() -> None:
    for path in sys.argv[1:]:
        with open(path, 'rb') as f:
            raw = f.read()
        newline = '\r\n' if b'\r\n' in raw else '\n'
        text = raw.decode('utf-8').replace('\r\n', '\n')
        result = process(text)
        if not result.endswith('\n'):
            result += '\n'
        data = result.replace('\n', newline).encode('utf-8')
        with open(path, 'wb') as f:
            f.write(data)
        print(f'stripped: {path}')


if __name__ == '__main__':
    main()
