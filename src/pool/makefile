fakepool: fakepool.cpp ../crypto/*
	cd ../crypto && $(MAKE) odocrypt.o KeccakP-800-reference.o
	$(CXX) -o fakepool fakepool.cpp ../crypto/odocrypt.o ../crypto/KeccakP-800-reference.o -pthread -std=c++11
