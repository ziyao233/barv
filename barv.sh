#!/bin/bash

#	barv
#	A RISC-V VM implementation in Bash script
#	This file is distributed under Mozilla Public License Version 2.0
#	Copyright (c) 2024 Yao Zi. All rights reserved.

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
	mem[$(($1 + 3))]=$((($2 >> 24) & 0xff))
	mem[$(($1 + 2))]=$((($2 >> 16) & 0xff))
	mem[$(($1 + 1))]=$((($2 >> 8) & 0xff))
	mem[$(($1 + 0))]=$((($2 >> 0) & 0xff))
}

# $1: addr
load_long() {
	local a=${mem[$(($1 + 0))]}
	local b=${mem[$(($1 + 1))]}
	local c=${mem[$(($1 + 2))]}
	local d=${mem[$(($1 + 3))]}
	fetched_data=$((($a << 0) | ($b << 8) | ($c << 16) | ($d << 24)))
}

load_into_memory() {
	local begin=$1
	local filename=$2

	local i=0
	for byte in `od -An -v -td1 $filename`; do
		mem[$i]=$(($byte & 0xff))
		i=$(($i + 1))
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

sign_extend20() {
	if [ $(($fetched_data & 0x80000)) != 0 ]; then
		fetched_data=$(($fetched_data | 0xfff00000))
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
	local r=$((($1 - $fetched_data) & 0xffffffff))
	local rs=$(($r & 0x80000000))
	local of=0
	if [ $(($1 & 0x80000000)) != $(($fetched_data & 0x80000000)) ]; then
		if [ $(($1 & 0x80000000)) == $rs ]; then
			of=0
		else
			of=$((0x80000000))
		fi
	fi

	[ $rs != $of ]
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
		if [ $(($fetched_data & 0x400)) != 0 ]; then
			# srai
			local sign=$(($rs1 & 0x80000000))
			fetched_data=$(($rs1 >> $shamt))
			if [ $sign != 0 ]; then
				local m=$(((1 << ($shamt + 1)) - 1))
				m=$(($m << (32 - $shamt)))
				fetched_data=$(($fetched_data | $m))
			fi
		else
			# srli
			fetched_data=$(($rs1 >> $shamt))
		fi
	esac
	limit_width
	set_to_rd
}

reg_ops() {
	load_from_rs1
	load_from_rs2

	case $((($inst >> 12) & 0x7)) in
	0)	# 000, add/sub
		if [ $(($inst & 0x40000000)) != 0 ]; then
			fetched_data=$(($rs1 - $rs2))
		else
			fetched_data=$(($rs1 + $rs2))
		fi ;;
	1)	# 001, sll
		fetched_data=$(($rs1 << ($rs2 & 0x1f))) ;;
	2)	# 010, slt
		fetched_data=$rs2
		if less_than_data_sign $rs1; then
			fetched_data=1
		else
			fetched_data=0
		fi ;;
	3)	# 011, sltu
		fetched_data=$rs2
		if less_than_data $rs1; then
			fetched_data=1
		else
			fetched_data=0
		fi ;;
	4)	# 100, xor
		fetched_data=$(($rs1 ^ $rs2)) ;;
	5)	# 101, srl/sra
		rs2=$(($rs2 & 0x1f))
		fetched_data=$(($rs1 >> $rs2))
		if [ $(($inst & 0x40000000)) != 0 ]; then
			local sign=$(($rs1 & 0x80000000))
			if [ $sign != 0 ]; then
				local m=$(((1 << ($rs2 + 1)) - 1))
				m=$(($m << (32 - $rs2)))
				fetched_data=$(($fetched_data | $m))
			fi
		fi ;;
	6)	# 110, or
		fetched_data=$(($rs1 | $rs2)) ;;
	7)	# 111, and
		fetched_data=$(($rs1 & $rs2)) ;;
	*)	unsupported_instruction ;;
	esac

	limit_width
	set_to_rd
}

load_short() {
	local a=${mem[$(($1 + 0))]}
	local b=${mem[$(($1 + 1))]}
	fetched_data=$(((a << 0) | (b << 8)))
}

unsupported_instruction() {
	echo unsupported instruction
	echo "native representation (inst: $inst), (pc: $reg_pc - 4)"
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
	mem[$(($1 + 0))]=$((($2 >> 0) & 0xff))
	mem[$(($1 + 1))]=$((($2 >> 8) & 0xff))
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

cond_branch() {
	local imm=$((($inst >> 31) << 11))
	imm=$(($imm | (($inst >> 21) & 0x3f0)))
	imm=$(($imm | (($inst >> 8) & 0xf)))
	imm=$(($imm | (($inst << 3) & 0x400)))
	imm=$(($imm << 1))
	fetched_data=$imm
	sign_extend12
	imm=$fetched_data

	load_from_rs1
	load_from_rs2

	local b=0
	case $((($inst >> 12) & 0x7)) in
	0)	# beq
		[ $rs1 == $rs2 ]
		b=$? ;;
	1)	# bne
		[ $rs1 != $rs2 ]
		b=$? ;;
	4)	# blt
		fetched_data=$rs2
		less_than_data_sign $rs1
		b=$? ;;
	5)	# bge
		if [ $rs1 != $rs2 ]; then
			fetched_data=$rs1
			less_than_data_sign $rs2
			b=$?
		fi ;;
	6)	# bltu
		fetched_data=$rs2
		less_than_data $rs1
		b=$? ;;
	7)	# bgeu
		if [ $rs1 != $rs2 ]; then
			fetched_data=$rs1
			less_than_data $rs2
			b=$?
		fi ;;
	*)	unsupported_instruction ;;
	esac

	if [ $b == 0 ]; then
		fetched_data=$(($imm + $reg_pc - 4))
		limit_width
		reg_pc=$fetched_data
	fi
	return 0
}

do_ecall() {
	local a0=${reg[10]}
	local a1=${reg[11]}
	case ${reg[10]} in
	1)	# print register
		printf "register print: %08x (%d)\n" $a1 $a1 ;;
	2)	# print character
		printf "\x$(printf %x $(($a1 & 0xff)))" ;;
	*)	echo unsupported ecall, a0 = $a0
		printf "pc=%08x\n" $(($reg_pc - 4))
	esac
}

while true; do
	fetch_inst

	case $(($inst & 0x7f)) in
	$((0x03)))	# load ops
		load_ops ;;
	$((0x0f)))	# fence
		;;
	$((0x13)))	# imm ops
		imm_ops ;;
	$((0x23)))	# store ops
		store_ops ;;
	$((0x33)))	# reg ops
		reg_ops ;;
	$((0x37)))	# lui
		fetched_data=$(($inst & 0xfffff000))
		set_to_rd ;;
	$((0x17)))	# auipc
		fetched_data=$((($inst & 0xfffff000) + $reg_pc - 4))
		limit_width
		set_to_rd ;;
	$((0x63)))	# conditional branching
		cond_branch ;;
	$((0x67)))	# jalr
		load_from_rs1
		fetched_data=$(($inst >> 20))
		sign_extend12
		r=$reg_pc
		fetched_data=$(($fetched_data + $rs1))
		limit_width
		reg_pc=$fetched_data
		fetched_data=$r
		set_to_rd ;;
	$((0x6f)))	# jal
		fetched_data=$(((($inst >> 31) << 19) | (($inst >> 21) & 0x3ff)))
		fetched_data=$(($fetched_data | (($inst >> 10) & 0x400)))
		fetched_data=$(($fetched_data | (($inst & 0xff000) >> 1)))
		sign_extend20
		fetched_data=$((($fetched_data << 1) + ($reg_pc - 4)))
		limit_width
		r=$reg_pc
		reg_pc=$fetched_data
		fetched_data=$r
		set_to_rd ;;
	$((0x73)))	# 0x73, ebreak/ecall
		if [ $(($inst >> 20)) == 0 ]; then
			# ecall
			if [ ${reg[10]} == 0 ]; then
				break;
			fi
			do_ecall
		else
			# ebreak
			dump_registers
		fi ;;
	*)
		unsupported_instruction ;;
	esac
done
