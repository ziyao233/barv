int print_int(int n);

int
main(void)
{
	int s = 0;
	for (int i = 1; i <= 100; i++)
		s += i;
	print_int(s);
	return 0;
}
