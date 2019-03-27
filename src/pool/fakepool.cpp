// Dummy pool for testing.  Generates random work to be solved.
// Copyright (C) 2019 MentalCollatz
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <stdint.h>
#include <fcntl.h>
#include <poll.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <thread>

#include "../crypto/hashodo.h"

const int MAINNET_EPOCH_LENGTH = 864000;
const int TESTNET_EPOCH_LENGTH = 86400;
const int DEFAULT_PORT = 17064;

int HexDigit(char c)
{
    if ('0' <= c && c <= '9')
        return c - '0';
    if ('a' <= c && c <= 'f')
        return 10 + c - 'a';
    if ('A' <= c && c <= 'F')
        return 10 + c - 'A';
    assert(false);
}

bool SendStr(int conn, const char *buf)
{
    int status;
    size_t len = strlen(buf);
    while (len)
    {
        status = send(conn, buf, len, 0);
        if (status == -1)
            return false;
        assert(status > 0);
        len -= status;
        buf += status;
    }
    return true;
}

bool HashLess(const uint8_t hash1[32], const uint8_t hash2[32])
{
    for (int i = 31; i >= 0; i--)
    {
        if (hash1[i] < hash2[i])
            return true;
        if (hash1[i] > hash2[i])
            return false;
    }
    return false;
}

#define CHECK(cond, msg) do {if (!(cond)) { perror(msg ": "); goto cleanup; } }while(0)

template<size_t bytes>
void ToHex(const uint8_t (&binStr)[bytes], char hexStr[], bool reversed = false)
{
    static const char* hexChar = "0123456789ABCDEF";
    char *opos = reversed ? hexStr + 2*bytes : hexStr;
    for (size_t i = 0; i < bytes; i++)
    {
        if (reversed) opos -= 2;
        opos[0] = hexChar[binStr[i] >> 4];
        opos[1] = hexChar[binStr[i] & 0xf];
        if (!reversed) opos += 2;
    }
    hexStr[2*bytes] = 0;
}

template<size_t bytes>
void FromHex(uint8_t (&binStr)[bytes], const char hexStr[])
{
    for (size_t i = 0; i < bytes; i++)
    {
        binStr[i] = 16*HexDigit(hexStr[2*i]) + HexDigit(hexStr[2*i+1]);
    }
}

uint64_t time_ms()
{
    timespec tm;
    clock_gettime(CLOCK_MONOTONIC, &tm);
    return tm.tv_sec*1000ULL + tm.tv_nsec / 1000000;
}

struct SocketLineReader
{
    SocketLineReader(int fd): fd(fd), closed(false) {}

    std::string ReadLine(int timeout_ms)
    {
        size_t pos = 0;
        while (true)
        {
            pos = buffer.find('\n', pos);
            if (pos != std::string::npos)
            {
                std::string res = buffer.substr(0, pos);
                buffer.erase(0, pos+1);
                return res;
            }
            pos = buffer.size();

            char buf[200];
            int status = recv(fd, buf, sizeof buf, MSG_DONTWAIT);
            if (status > 0)
            {
                buffer.append(buf, status);
                continue;
            }
            if (status == 0)
            {
                closed = true;
                return "";
            }
            if (errno != EAGAIN && errno != EWOULDBLOCK)
            {
                perror("recv failed");
                closed = true;
                return "";
            }
            if (timeout_ms <= 0)
            {
                return "";
            }

            uint64_t started = time_ms();
            struct pollfd pfd;
            pfd.fd = fd;
            pfd.events = POLLIN;
            if (!poll(&pfd, 1, timeout_ms))
                return "";
            uint64_t elapsed = time_ms() - started;
            timeout_ms -= elapsed;
        }
    }

    int fd;
    std::string buffer;
    bool closed;
};


void FakePool(int conn, int epochLength)
{
    uint8_t header[80];
    uint8_t target[32];
    uint32_t key;
    SocketLineReader sock(conn);

    while (true)
    {
        for (int i = 0; i < 80; i++)
            header[i] = (i >= 76) ? 0 : (rand() & 0xff);
        for (int i = 0; i < 32; i++)
            target[i] = (i >= 29) ? 0 : (rand() & 0xff);
        key = time(NULL);
        key -= key % epochLength;
        char headerHex[161], targetHex[65];
        ToHex(header, headerHex);
        ToHex(target, targetHex, true);
        char workBuf[256];
        sprintf(workBuf, "work %s %s %d\n", headerHex, targetHex, key);
        if (!SendStr(conn, workBuf))
            break;

        int timeout = rand() % 10000;
        std::string command = sock.ReadLine(timeout);
        if (sock.closed)
            break;
        if (command.size())
        {
            if (command.size() >= 167 && command.substr(0, 7) == "submit ")
            {
                uint8_t solvedHeader[80];
                FromHex(solvedHeader, command.c_str()+7);
                const char* result;
                if (memcmp(solvedHeader, header, 76) != 0)
                {
                    result = "stale";
                }
                else
                {
                    uint8_t hash[32];
                    HashOdo(hash, solvedHeader, solvedHeader+80, key);
                    if (!HashLess(target, hash))
                    {
                        result = "accepted";
                    }
                    else
                    {
                        char hexBuf[161];
                        ToHex(solvedHeader, hexBuf);
                        fprintf(stderr, "Bad submission: %s\n", hexBuf);
                        fprintf(stderr, "Seed = %d\n", key);
                        ToHex(target, hexBuf, true);
                        fprintf(stderr, "Target = %s\n", hexBuf);
                        ToHex(hash, hexBuf, true);
                        fprintf(stderr, "Hash   = %s\n", hexBuf);
                        result = "bad";
                    }
                }
                sprintf(workBuf, "result %s\n", result);
                if (!SendStr(conn, workBuf))
                    break;
            }
            else
            {
                fprintf(stderr, "Unknown command: %s\n", command.c_str());
            }
        }
    }
    close(conn);
    printf("closed connection\n");
}

int usage(const char* argv[])
{
    fprintf(stderr, "Usage: %s [--testnet] [port]\n", argv[0]);
    return 1;
}

int main(int argc, const char* argv[])
{
    int listenPort = DEFAULT_PORT;
    int epochLength = MAINNET_EPOCH_LENGTH;
    for (int i = 1; i < argc; i++)
    {
        if (strcmp(argv[i], "--testnet") == 0)
            epochLength = TESTNET_EPOCH_LENGTH;
        else
        {
            listenPort = strtoul(argv[i], NULL, 0);
            if (1024 > listenPort || listenPort >= 49152)
            {
                return usage(argv);
            }
        }
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    assert(fd != -1);
    sockaddr_in addr;
    socklen_t addrlen = sizeof addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(listenPort);
    // change to INADDR_ANY if you want to run on a remote machine
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    memset(addr.sin_zero, 0, sizeof addr.sin_zero);

    int optval = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof optval);

    int status = bind(fd, (sockaddr*)&addr, sizeof addr);
    if (status)
    {
        perror("bind failed");
        return 1;
    }
    status = listen(fd, 10);
    if (status)
    {
        perror("listen failed");
        return 1;
    }
    while (true)
    {
        status = accept(fd, (sockaddr*)&addr, &addrlen);
        if (status == -1)
        {
            perror("accept failed");
            return 1;
        }
        std::thread(FakePool, status, epochLength).detach();
    }
}
