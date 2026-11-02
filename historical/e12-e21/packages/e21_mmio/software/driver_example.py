"""Illustrative ordered, blocking backend API; no real OS/CPU bus implementation.
read32/write32 MUST wait for MMIO response and raise on nonzero rsp_code.
After reset/timeout, drain/reset transport and reload; do not blindly retry commands.
"""
def status(io):
    raw = io.read32(0x004)
    if raw & (1 << 5):
        raise RuntimeError(f'Loader error {(raw >> 6) & 7}')
    return raw


def load_and_start(io, *, validated_values, digest, generation, channels, height):
    # Caller supplies E19/E20 validated in-memory values, not an unchecked PASS file.
    if len(digest) != 32:
        raise ValueError('SHA256 identity must have 32 bytes')
    for a, v in ((8, generation), (12, generation), (16, channels | height << 16), (20, 1)):
        io.write32(a, v)
    identity = int.from_bytes(digest, 'big')
    for i in range(8):
        io.write32(0x40 + 4*i, (identity >> (32*i)) & 0xffffffff)
    io.write32(0, 1)  # BEGIN
    status(io)
    if io.read32(0x20) != generation:
        raise RuntimeError('Active generation mismatch')
    for i in range(8):
        if io.read32(0x60 + 4*i) != (identity >> (32*i)) & 0xffffffff:
            raise RuntimeError('Active digest mismatch')
    count = 0
    for role, words in enumerate(validated_values):
        for address, raw32 in enumerate(words):
            io.write32(0x18, role << 16 | address)
            io.write32(0x1c, raw32)
            io.write32(0, 2)  # WRITE_ONE
            status(io)       # accepted native write can still fail semantic validation
            count += 1
    if io.read32(0x24) != count:
        raise RuntimeError('Native write count mismatch')
    io.write32(0, 3)  # COMMIT
    if not status(io) & (1 << 1):
        raise RuntimeError('Not prepared')
    io.write32(0, 4)  # START; output stream consumer must be ready independently
    status(io)


def wait_and_ack(io, max_polls):
    for _ in range(max_polls):
        if status(io) & (1 << 4):
            io.write32(0, 5)
            return
    raise TimeoutError('Do not retry START automatically; reconcile/reset session')
