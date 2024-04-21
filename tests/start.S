		.global		_start
		.global		print_int

		.section	.text.start
_start:
		li		sp,		0xfff0

		call		main

		xor		a0,		a0,		a0
		ecall

print_int:
		mv		a1,		a0
		li		a0,		1
		ecall
		ret
