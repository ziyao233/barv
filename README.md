# barv

A rv32i virtual machine, implemented in Bash.

## Dependency

Bash and coreutils. I did this mess on Alpine Linux edge with busybox and
bash 5.2.26 and everything worked well.

## Usage

```
 $ barv.sh BINARY
```

## Memory Map and Boot Up

The binary specified as argument will be loaded into memory, starting from
0x00000000. PC is set to 0 when the virtual machine starts.

## Environment Call

Some functionalities are provided through `ecall`. `a0` contains ecall number.

### ecall Number

- `0`: system shutdown (exit the VM)
- `1`: register dump (dump out `a1`)
- `2`: ASCII putchar (character is stored in `a1`)

`ebreak` could be used to print a snapshot of registers.

## Tests

barv has passed [a port of riscv-tests](https://github.com/ziyao233/barv-rvtests).
But there are still bugs I think.
