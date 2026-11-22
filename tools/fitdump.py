#!/usr/bin/env python3
"""Prints the developer fields of a FIT activity file.

usage: fitdump.py <file.fit> [--all]

Developer fields are what a Connect IQ data field adds to a recording. This shows what
is really in the file, whatever a viewer chooses to display. Consecutive messages with
the same values are folded into one line; --all prints every message.
"""
import struct
import sys

# FIT base type number -> (name, struct code, size, value that means "no value")
BASE = {
    0: ('enum', 'B', 1, 0xFF), 1: ('sint8', 'b', 1, 0x7F), 2: ('uint8', 'B', 1, 0xFF),
    3: ('sint16', 'h', 2, 0x7FFF), 4: ('uint16', 'H', 2, 0xFFFF),
    5: ('sint32', 'i', 4, 0x7FFFFFFF), 6: ('uint32', 'I', 4, 0xFFFFFFFF),
    7: ('string', 's', 1, None), 8: ('float32', 'f', 4, None), 9: ('float64', 'd', 8, None),
    10: ('uint8z', 'B', 1, 0), 11: ('uint16z', 'H', 2, 0), 12: ('uint32z', 'I', 4, 0),
    13: ('byte', 'B', 1, 0xFF), 14: ('sint64', 'q', 8, 0x7FFFFFFFFFFFFFFF),
    15: ('uint64', 'Q', 8, 0xFFFFFFFFFFFFFFFF), 16: ('uint64z', 'Q', 8, 0),
}
MESSAGES = {18: 'session', 19: 'lap', 20: 'record'}
FIELD_DESCRIPTION = 206
TIMESTAMP = 253


def value(raw, base, endian):
    """Decodes one field; None stands for FIT's "no value"."""
    _, code, size, invalid = BASE[base & 0x1F]
    if code == 's':
        return raw.split(b'\0')[0].decode('utf-8', 'replace')
    count = len(raw) // size
    values = []
    for item in struct.unpack(endian + code * count, raw[:count * size]):
        values.append(None if item == invalid or item != item else item)
    return values[0] if count == 1 else values


def messages(data):
    """Yields (message number, byte order, native fields, raw developer fields)."""
    header = data[0]
    end = header + struct.unpack_from('<I', data, 4)[0]
    definitions = {}
    pos = header
    while pos < end:
        head = data[pos]
        pos += 1
        if head & 0x80:                       # data message with a compressed timestamp
            local = (head >> 5) & 0x03
        elif head & 0x40:                     # definition message
            endian = '>' if data[pos + 1] else '<'
            number = struct.unpack_from(endian + 'H', data, pos + 2)[0]
            count = data[pos + 4]
            pos += 5
            fields = [tuple(data[pos + 3 * i:pos + 3 * i + 3]) for i in range(count)]
            pos += 3 * count
            developer = []
            if head & 0x20:                   # developer fields follow
                count = data[pos]
                pos += 1
                developer = [tuple(data[pos + 3 * i:pos + 3 * i + 3]) for i in range(count)]
                pos += 3 * count
            definitions[head & 0x0F] = (number, endian, fields, developer)
            continue
        else:                                 # plain data message
            local = head & 0x0F
        number, endian, fields, developer = definitions[local]
        native = {}
        for field, size, base in fields:
            native[field] = value(data[pos:pos + size], base, endian)
            pos += size
        raw = {}
        for field, size, index in developer:
            raw[(index, field)] = data[pos:pos + size]
            pos += size
        yield number, endian, native, raw


def main():
    paths = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(paths) != 1:
        sys.exit(__doc__)
    data = open(paths[0], 'rb').read()
    if data[8:12] != b'.FIT':
        sys.exit('not a FIT file: ' + paths[0])

    described = {}   # (developer data index, field number) -> (name, units, base type)
    seen_in = {}     # same key -> names of the messages that carry the field
    rows = {}        # message name -> [(timestamp, text)]
    for number, endian, native, raw in messages(data):
        if number == FIELD_DESCRIPTION:
            described[(native.get(0), native.get(1))] = (
                native.get(3) or '?', native.get(8) or '', native.get(2) or 13)
        if not raw:
            continue
        name = MESSAGES.get(number, 'message %d' % number)
        parts = []
        for key in sorted(raw):
            field, _, base = described.get(key, ('field %d.%d' % key, '', 13))
            seen_in.setdefault(key, set()).add(name)
            decoded = value(raw[key], base, endian)
            parts.append('%s=%s' % (field, '-' if decoded is None else decoded))
        rows.setdefault(name, []).append((native.get(TIMESTAMP), '  '.join(parts)))

    if not described:
        print('no developer fields in this file')
        return
    print('developer fields:')
    for key in sorted(described):
        field, units, base = described[key]
        where = ', '.join(sorted(seen_in.get(key, []))) or 'no message'
        print('  %-20s %-8s %-6s in %s' % (field, BASE[base & 0x1F][0], units, where))
    fold = '--all' not in sys.argv
    for name, items in rows.items():
        print('%s: %d message(s)' % (name, len(items)))
        stamps = [stamp for stamp, _ in items if stamp is not None]
        start = stamps[0] if stamps else None
        runs = []    # [offset, text, count]
        for index, (stamp, text) in enumerate(items):
            if fold and runs and runs[-1][1] == text:
                runs[-1][2] += 1
                continue
            offset = stamp - start if stamp is not None and start is not None else index
            runs.append([offset, text, 1])
        for offset, text, count in runs:
            print('  +%4ds  %s%s' % (offset, text, '   x%d' % count if count > 1 else ''))


if __name__ == '__main__':
    main()
