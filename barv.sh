#!/bin/bash

#	barv
#	A RISC-V VM implementation in Bash script
#	This file is distributed under Mozilla Public License Version 2.0
#	Copyright (c) 2024 Yao Zi. All rights reserved.

set -e

memsize=$((1024 * 64))
mem=()
reg=()
fetched_inst=0		# fetched instruction
fetched_data=0		# fetched data
reg_pc=0	# Start from 0x00000000

# Initialize memory
for i in `seq 1 $memsize`; do
	mem[$((i - 1))]=0
done

# Initialize register
for i in `seq 1 32`; do
	reg[$((i - 1))]=0
done

echo Memory size: ${#mem[@]} Bytes
echo Register Num: ${#reg[@]}

# $1: addr, $2: data
store_long_arg() {
	mem[$(($1 + 0))]=$((($2 >> 24) & 0xff))
	mem[$(($1 + 1))]=$((($2 >> 16) & 0xff))
	mem[$(($1 + 2))]=$((($2 >> 8) & 0xff))
	mem[$(($1 + 3))]=$((($2 >> 0) & 0xff))
}

# $1: addr
load_long() {
	local a=${mem[$(($1 + 0))]}
	local b=${mem[$(($1 + 1))]}
	local c=${mem[$(($1 + 2))]}
	local d=${mem[$(($1 + 3))]}
	fetched_data=$((($a << 24) | ($b << 16) | ($c << 8) | ($d << 0)))
}

load_into_memory() {
	local begin=$1
	local filename=$2

	local i=0
	for long in `hexdump -ve '"%d "' $filename`; do
		store_long_arg $i $long
		i=$(($i + 4))
	done
}

if [ x$1 = x ]; then
	echo "Specified a binary file to load"
	exit -1
fi

load_into_memory 0 $1

fetch_inst() {
	load_long $reg_pc
	inst=$fetched_data
	reg_pc=$(($reg_pc + 4))
}

# $1: register
set_to_reg() {
	reg[$1]=$fetched_data
}

# $1: register
load_from_reg() {
	if [ $1 == 0 ]; then
		fetched_data=0
	else
		fetched_data=${reg[$1]}
	fi
}

dump_registers() {
	for i in `seq 1 32`; do
		load_from_reg $((i - 1))
		printf "x%d = %08x\t" $((i - 1)) $fetched_data
		if [ $((i % 4)) == 0 ]; then
			if [ $i == 0 ]; then
				continue
			fi
			printf "\n"
		fi
	done
}

limit_width() {
	fetched_data=$(($fetched_data & 0xffffffff))
}

sign_extend8() {
	if [ $(($fetched_data & 0x80)) == 128 ]; then
		fetched_data=$(($fetched_data | 0xffffff00))
	fi
}

sign_extend12() {
	if [ $(($fetched_data & 0x800)) == 2048 ]; then
		fetched_data=$(($fetched_data | 0xfffff000))
	fi
}

sign_extend16() {
	if [ $(($fetched_data & 0x8000)) == 32768 ]; then
		fetched_data=$(($fetched_data | 0xffff0000))
	fi
}

set_to_rd() {
	set_to_reg $((($inst >> 7) & 0x1f))
}

load_from_rs1() {
	load_from_reg $((($inst >> 15) & 0x1f))
	rs1=$fetched_data
}

load_from_rs2() {
	load_from_reg $((($inst >> 20) & 0x1f))
	rs2=$fetched_data
}

# $1: left
less_than_data() {
	[ $1 -lt $fetched_data ]
	return
}

# $1: left
less_than_data_sign() {
	local r=$(($1 - $fetched_data))
	local rs=$(($r & 0x80000000))
	local of=0
	if [ $(($1 & 0x80000000)) == $(($fetched_data & 0x80000000)) ]; then
		if [ $(($1 & 0x80000000)) == $rs ]; then
			of=0
		else
			of=$((0x80000000))
		fi
	fi

	[ $rs != $(($of << 31)) ]
	return
}

imm_ops() {
	load_from_rs1
	fetched_data=$(($inst >> 20))
	case $((($inst >> 12) & 0x7)) in
	0)	# 000, addi
		sign_extend12
		fetched_data=$(($fetched_data + $rs1)) ;;
	2)	# 010, slti
		sign_extend12
		if less_than_data_sign $rs1; then
			fetched_data=1
		else
			fetched_data=0
		fi ;;
	3)	# 011, sltiu
		sign_extend12
		if less_than_data $rs1; then
			fetched_data=1
		else
			fetched_data=0
		fi ;;
	4)	# 100, xori
		sign_extend12
		fetched_data=$(($fetched_data ^ $rs1)) ;;
	6)	# 110, ori
		sign_extend12
		fetched_data=$(($fetched_data | $rs1)) ;;
	7)	# 111, andi
		sign_extend12
		fetched_data=$(($fetched_data & $rs1)) ;;

	1)	# 001, slli
		fetched_data=$(($fetched_data & 0x1f))
		fetched_data=$(($rs1 << $fetched_data)) ;;
	5)	# 101, srli, srai
		local shamt=$(($fetched_data & 0x1f))
		echo shamt: $shamt
		if [ $(($fetched_data & 0x400)) != 0 ]; then
			echo srai
			# srai
			local sign=$(($rs1 & 0x80000000))
			fetched_data=$(($rs1 >> $shamt))
			if [ $sign != 0 ]; then
				local m=$(((1 << ($shamt + 1)) - 1))
				m=$((m << (32 - $shamt)))
				fetched_data=$(($fetched_data | m))
			fi
		else
			# srli
			echo srli
			fetched_data=$(($rs1 >> $shamt))
		fi
	esac
	limit_width
	set_to_rd
}

load_short() {
	local a=${mem[$(($1 + 0))]}
	local b=${mem[$(($1 + 1))]}
	fetched_data=$(((a << 8) | (b << 0)))
}

unsupported_instruction() {
	echo unsupported instruction
	echo "native representation (inst: $inst), (pc: $pc - 4)"
	printf "instruction %08x, pc=%08x\n" $inst $(($reg_pc - 4))
	exit -1
}

load_ops() {
	load_from_rs1
	fetched_data=$(($inst >> 20))
	sign_extend12
	fetched_data=$(($rs1 + $fetched_data))
	limit_width
	local addr=$fetched_data

	case $((($inst >> 12) & 0x7)) in
	0)	# 000, lb
		fetched_data=${mem[$addr]}
		sign_extend8 ;;
	1)	# 001, lh
		load_short $addr
		sign_extend16 ;;
	2)	# 010, lw
		load_long $addr ;;
	4)	# 100, lbu
		fetched_data=${mem[$addr]} ;;
	5)	# 101, lhu
		load_short $addr ;;
	*)
		unsupported_instruction ;;
	esac

	set_to_rd
}

# $1: addr, $2: data
store_short_arg() {
	mem[$(($1 + 0))]=$((($2 >> 8) & 0xff))
	mem[$(($1 + 1))]=$((($2 >> 0) & 0xff))
}

store_ops() {
	load_from_rs1
	fetched_data=$((($inst & 0xff000000) >> 20))
	fetched_data=$(($fetched_data | (($inst >> 7) & 0x1f)))
	sign_extend12
	fetched_data=$(($rs1 + $fetched_data))
	limit_width
	local addr=$fetched_data

	load_from_rs2
	case $((($inst >> 12) & 0x7)) in
	0)	# 000, sb
		mem[$addr]=$(($rs2 & 0xff)) ;;
	1)	# 001, sh
		store_short_arg $addr $rs2 ;;
	2)	# 010, sw
		store_long_arg $addr $rs2 ;;
	*)	unsupported_instruction ;;
	esac
}

while true; do
	fetch_inst

	case $(($inst & 0x7f)) in
	$((0x03)))	# load ops
		load_ops ;;
	$((0x23)))	# store ops
		store_ops ;;
	$((0x37)))	# lui
		fetched_data=$(($inst & 0xfffff000))
		set_to_rd ;;
	$((0x17)))	# auipc
		fetched_data=$((($inst & 0xfffff000) + $reg_pc - 4))
		limit_width
		set_to_rd ;;
	$((0x13)))	# imm ops
		imm_ops ;;
	$((0x73)))	# 0x73, ebreak/ecall
		if [ $(($inst >> 20)) == 0 ]; then
			break;
		else
			dump_registers
		fi ;;
	*)
		unsupported_instruction ;;
	esac
done

echo "shutdown with ecall"
dump_registers
