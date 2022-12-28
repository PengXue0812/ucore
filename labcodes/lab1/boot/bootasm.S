#include <asm.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.set PROT_MODE_CSEG,        0x8                     # kernel code segment selector
.set PROT_MODE_DSEG,        0x10                    # kernel data segment selector
.set CR0_PE_ON,             0x1                     # protected mode enable flag

# start address should be 0:7c00, in real mode, the beginning address of the running bootloader
.globl start
start:
.code16                                             # Assemble for 16-bit mode
    cli                                             # Disable interrupts
    cld                                             # String operations increment

    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data Segment
    movw %ax, %es                                   # -> Extra Segment
    movw %ax, %ss                                   # -> Stack Segment

    # Enable A20:
    #  For backwards compatibility with the earliest PCs, physical
    #  address line 20 is tied low, so that addresses higher than
    #  1MB wrap around to zero by default. This code undoes this.

# 启动 A20
seta20.1:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al                                 
    jnz seta20.1                                    # 如果 %al 第2位（低位)为1，则循环
    # 否则，8042输入缓冲区为空，可以继续执行
    # 将值 0xd1 写入端口 0x64 
    # 0xd1命令：向8042的p2端口写入数据
    movb $0xd1, %al                                 # 0xd1 -> port 0x64
    outb %al, $0x64                                 # 0xd1 means: write data to 8042's P2 port

seta20.2:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.2

    # 将值 0xdf 写入端口 0x60
    # 设置A20位位为1
    movb $0xdf, %al                                 # 0xdf -> port 0x60
    outb %al, $0x60                                 # 0xdf = 11011111, means set P2's A20 bit(the 1 bit) to 1

    # Switch from real to protected mode, using a bootstrap GDT
    # and segment translation that makes virtual addresses
    # identical to physical addresses, so that the
    # effective memory map does not change during the switch.

    lgdt gdtdesc # 载入GDT

    # 将 CR0 的保护模式(PE)标志 设置为1
    movl %cr0, %eax
    orl $CR0_PE_ON, %eax # $CR0_PE_ON常数表示CR0寄存器的PE位
    movl %eax, %cr0

    # Jump to next instruction, but in 32-bit code segment.
    # Switches processor into 32-bit mode.
    # 跳转到 32 位代码段的指令处，并将 CPU 进入32位模式
    ljmp $PROT_MODE_CSEG, $protcseg

.code32                                             # Assemble for 32-bit mode
protcseg:
    # Set up the protected-mode data segment registers
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    movw %ax, %fs                                   # -> FS
    movw %ax, %gs                                   # -> GS
    movw %ax, %ss                                   # -> SS: Stack Segment

    # Set up the stack pointer and call into C. The stack region is from 0--start(0x7c00)
    movl $0x0, %ebp
    movl $start, %esp
    call bootmain

    # If bootmain returns (it shouldn't), loop.
spin:
    jmp spin

# Bootstrap GDT
# 初始化 GDT 表
.p2align 2                                          # 强制将代码对齐到4字节边界
gdt:
    SEG_NULLASM                                     # 空段
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # 可执行代码段
    SEG_ASM(STA_W, 0x0, 0xffffffff)                 # 可写数据段

# gdtdesc变量，包含了GDT的大小和GDT的地址
gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1  0x17表示3个描述符
    .long gdt                                       # address gdt
