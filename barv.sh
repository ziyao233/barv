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
store_quad_arg() {
	mem[$(($1 + 0))]=$((($2 >> 24) & 0xff))
	mem[$(($1 + 1))]=$((($2 >> 16) & 0xff))
	mem[$(($1 + 2))]=$((($2 >> 8) & 0xff))
	mem[$(($1 + 3))]=$((($2 >> 0) & 0xff))
}

# $1: addr
load_quad() {
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
	for quad in `hexdump -ve '"%d "' $filename`; do
		store_quad_arg $i $quad
		i=$(($i + 4))
	done
}

if [ x$1 = x ]; then
	echo "Specified a binary file to load"
	exit -1
fi

load_into_memory 0 $1

fetch_inst() {
	load_quad $reg_pc
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

sign_extend12() {
	if [ $(($fetched_data & 0x800)) == 2048 ]; then
		fetched_data=$(($fetched_data | 0xfffff000))
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

load_ops() {
}

while true; do
	fetch_inst

	case $(($inst & 0x7f)) in
	$((0x37)))	# lui
		fetched_data=$(($inst & 0xfffff000))
		set_to_rd ;;
	$((0x17)))	# auipc
		fetched_data=$((($inst & 0xfffff000) + $reg_pc))
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
		echo "native representation (inst: $inst) (pc: $reg_pc)"
		printf "unsupported instruction %08x, pc=%08x\n" $inst $reg_pc
		exit -1 ;;
	esac
done

echo "shutdown with ecall"
dump_registers
