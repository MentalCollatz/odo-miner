odocrypt.o: odocrypt.cpp odocrypt.h
	$(CXX) -c -o odocrypt.o odocrypt.cpp -g -fsanitize=address

KeccakP-800-reference.o: KeccakP-800-reference.c KeccakP-800-SnP.h brg_endian.h
	$(CC) -c -o KeccakP-800-reference.o KeccakP-800-reference.c -g -fsanitize=address
