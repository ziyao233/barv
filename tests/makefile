CROSS_PREFIX	= riscv-none-elf-
CC		= $(CROSS_PREFIX)gcc
CCAS		= $(CC)
LD		= $(CROSS_PREFIX)ld
OBJCOPY		= $(CROSS_PREFIX)objcopy
HOSTCC		= gcc
BOARD		= virt

LDSCRIPT	= link.ld

CFLAGS		= -nostdlib -nostdinc -I$(INCLUDE)	\
		  -I$(THISBOARD)/ -march=rv32i		\
		  -mcmodel=medany -mabi=ilp32 -g -O0
LDFLAGS		= -T $(LDSCRIPT)

OBJS		:= start.o main.o
KERNEL		:= test.elf
BINARY		:= test.bin

default: build

build: $(BINARY)

$(BINARY): $(KERNEL)
	$(OBJCOPY) $(KERNEL) -O binary -j .text -j .data $(BINARY)

$(KERNEL): $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $(KERNEL)

clean:
	-rm $(OBJS)

disbuild: clean
	-rm $(KERNEL)

%.o: %.S
	$(CCAS) $< -c $(CFLAGS) -o $@

%.o: %.c
	$(CC) $< -c $(CFLAGS) -o $@
