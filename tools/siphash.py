"""SipHash-2-4, checked against the reference vectors in tools/check.py."""
import struct

MASK = (1 << 64) - 1


def rotl(x, b):
    return ((x << b) | (x >> (64 - b))) & MASK


def siphash24(key: bytes, msg: bytes) -> int:
    k0, k1 = struct.unpack("<QQ", key)
    v0, v1 = k0 ^ 0x736F6D6570736575, k1 ^ 0x646F72616E646F6D
    v2, v3 = k0 ^ 0x6C7967656E657261, k1 ^ 0x7465646279746573

    def rnd():
        nonlocal v0, v1, v2, v3
        v0 = (v0 + v1) & MASK; v1 = rotl(v1, 13); v1 ^= v0; v0 = rotl(v0, 32)
        v2 = (v2 + v3) & MASK; v3 = rotl(v3, 16); v3 ^= v2
        v0 = (v0 + v3) & MASK; v3 = rotl(v3, 21); v3 ^= v0
        v2 = (v2 + v1) & MASK; v1 = rotl(v1, 17); v1 ^= v2; v2 = rotl(v2, 32)

    n = len(msg)
    tail = msg[n - n % 8:] + bytes(8 - n % 8 - 1) + bytes([n & 0xFF]) if n % 8 != 7 else msg[n - n % 8:] + bytes([n & 0xFF])
    blocks = [msg[i:i + 8] for i in range(0, n - n % 8, 8)] + [tail]
    for b in blocks:
        m = struct.unpack("<Q", b)[0]
        v3 ^= m; rnd(); rnd(); v0 ^= m
    v2 ^= 0xFF
    for _ in range(4):
        rnd()
    return v0 ^ v1 ^ v2 ^ v3
