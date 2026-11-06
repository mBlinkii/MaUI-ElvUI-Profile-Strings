"""
Reader for WoW SavedVariables files (the Lua subset the client writes).

    python -I Installer/tools/savedvars.py <SavedVariables.lua>   lists the top-level tables and their keys
"""

import re
import sys

TOKEN = re.compile(r"""
    \s+ | --[^\n]* |
    (?P<str>"(?:\\.|[^"\\])*") |
    (?P<num>-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<sym>[{}\[\]=,;])
""", re.X)

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\n": "\n"}


def unescape(body):
    out, i = [], 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt.isdigit():
            m = re.match(r"\d{1,3}", body[i + 1:])
            out.append(chr(0xDC00 + int(m.group())) if int(m.group()) >= 128 else chr(int(m.group())))
            i += 1 + len(m.group())
        else:
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
    # bytes >= 128 written as escapes are kept as surrogates, like convert.py does
    return "".join(out)


def tokenize(text):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError("bad input at %d: %r" % (pos, text[pos:pos + 30]))
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)


class Parser:
    def __init__(self, text):
        self.tokens = list(tokenize(text))
        self.pos = 0

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else (None, None)

    def next(self):
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def expect(self, value):
        tok = self.next()
        if tok[1] != value:
            raise ValueError("expected %s, got %s" % (value, tok))

    def value(self):
        kind, val = self.next()
        if kind == "str":
            return unescape(val[1:-1])
        if kind == "num":
            n = float(int(val, 16)) if val.lower().startswith(("0x", "-0x")) else float(val)
            return int(n) if n == int(n) and "." not in val and "e" not in val.lower() else n
        if kind == "name":
            return {"true": True, "false": False, "nil": None}[val]
        if val == "{":
            return self.table()
        raise ValueError("unexpected %s" % val)

    def table(self):
        result, index = {}, 1
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.next()
                key = self.value()
                self.expect("]")
                self.expect("=")
                val = self.value()
                if val is not None:
                    result[key] = val
            else:
                val = self.value()
                if val is not None:
                    result[index] = val
                index += 1
            if self.peek()[1] in (",", ";"):
                self.next()
        self.next()
        return result

    def file(self):
        result = {}
        while self.pos < len(self.tokens):
            _, name = self.next()
            self.expect("=")
            result[name] = self.value()
        return result


def load(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()
    # raw bytes >= 128 outside escapes are valid UTF-8 in practice; keep them as text
    return Parser(text).file()


if __name__ == "__main__":
    data = load(sys.argv[1])
    for name, table in data.items():
        print(name)
        if isinstance(table, dict):
            for key, val in table.items():
                if isinstance(val, dict):
                    print("   ", repr(key), "->", ", ".join(map(repr, list(val.keys())[:40])))
