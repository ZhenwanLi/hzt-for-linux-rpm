#!/usr/bin/env python3
"""清除 ELF64 共享库的 PT_GNU_STACK 可执行位（RWE -> RW）。

为什么需要：
    某些为老版本 glibc 打包的 .so 把栈标记为 RWE。在 glibc 2.43 +
    SELinux Enforcing 的系统上，dlopen() 这类库会失败，而上游程序不检查
    返回值，表现为「启动后静默退出」。

用法：
    ./gnu-stack-rw.py path/to/lib.so
"""
import struct
import sys

PT_GNU_STACK = 0x6474E551
PF_X = 0x1

ELFCLASS64 = 2


def patch(path: str) -> int:
    with open(path, "rb") as fh:
        data = bytearray(fh.read())

    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != ELFCLASS64:
        print(f"{path}: 不是 ELF64 文件，跳过")
        return 0

    e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
    e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
    e_phnum = struct.unpack_from("<H", data, 0x38)[0]

    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if struct.unpack_from("<I", data, off)[0] != PT_GNU_STACK:
            continue

        flags = struct.unpack_from("<I", data, off + 4)[0]
        if not flags & PF_X:
            print(f"{path}: GNU_STACK 已是不可执行 (0x{flags:x})，无需修改")
            return 0

        struct.pack_into("<I", data, off + 4, flags & ~PF_X)
        with open(path, "wb") as fh:
            fh.write(data)
        print(f"{path}: GNU_STACK 0x{flags:x} -> 0x{flags & ~PF_X:x}")
        return 0

    print(f"{path}: 未找到 PT_GNU_STACK，跳过")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("用法: gnu-stack-rw.py <elf64.so>")
    sys.exit(patch(sys.argv[1]))
