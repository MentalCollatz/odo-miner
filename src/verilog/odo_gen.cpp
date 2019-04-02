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

#include "../crypto/odocrypt.h"

#include <cassert>
#include <cstdio>
#include <cstdlib>

class OdoVerilog: public OdoCrypt
{
public:
    OdoVerilog(uint32_t seed): OdoCrypt(seed) {}
    void Generate(int throughput, const char* prefix = NULL, FILE* f = stdout) const;
};

#define NIBBLES(x) x, (1 + ((x)-1) / 4)

template<typename T, size_t sz1, size_t sz2>
void GenerateSboxes(const T (&sbox)[sz1][sz2], bool dual_port, const char* prefix, const char* suffix, FILE* f)
{
    int width = 0;
    while ((1 << width) < sz2)
        width++;
    assert((1 << width) == sz2);
    for (int i = 0; i < sz1; i++)
    {
        if (!dual_port)
        {
            fprintf(f, "module %ssbox_%s%d(clk, in, out);\n", prefix, suffix, i);
            fprintf(f, "    input clk;\n");
            fprintf(f, "    input [%d:0] in;\n", width-1);
            fprintf(f, "    output reg [%d:0] out;\n", width-1);
            fprintf(f, "    reg [%d:0] mem[0:%zd];\n", width-1, sz2-1);
            fprintf(f, "    always @(posedge clk) begin\n");
            fprintf(f, "        out <= mem[in];\n");
            fprintf(f, "    end\n");
        }
        else
        {
            fprintf(f, "module %ssbox_%s%d(clk, a_in, b_in, a_out, b_out);\n", prefix, suffix, i);
            fprintf(f, "    input clk;\n");
            fprintf(f, "    input [%d:0] a_in;\n", width-1);
            fprintf(f, "    output reg [%d:0] a_out;\n", width-1);
            fprintf(f, "    input [%d:0] b_in;\n", width-1);
            fprintf(f, "    output reg [%d:0] b_out;\n", width-1);
            fprintf(f, "    reg [%d:0] mem[0:%zd];\n", width-1, sz2-1);
            fprintf(f, "    always @(posedge clk) begin\n");
            fprintf(f, "        a_out <= mem[a_in];\n");
            fprintf(f, "        b_out <= mem[b_in];\n");
            fprintf(f, "    end\n");
        }
        fprintf(f, "    initial begin\n");
        for (int j = 0; j < sz2; j++)
        {
            fprintf(f, "        mem[%d] = %d'h%0*x;\n", j, NIBBLES(width), sbox[i][j]);
        }
        fprintf(f, "    end\n");
        fprintf(f, "endmodule\n\n");
    }
}

int gcd(int a, int b)
{
    return b == 0 ? a : gcd(b, a%b);
}

void OdoVerilog::Generate(int throughput, const char* prefix, FILE* f) const
{
    if (!prefix) prefix = "";
    
    int unrolling = (ROUNDS-1) / throughput + 1;
    int extra_delay = 0;
    while (gcd(throughput, 2*unrolling+extra_delay) != 1)
        extra_delay++;
    int periods = (ROUNDS-1) / unrolling + 1;
    int latency = 2*ROUNDS + (periods-1) * extra_delay + 1;
    int period_bits = 1;
    while ((1 << period_bits) < periods)
        period_bits++;

    // pre-mix
    fprintf(f, "module %spre_mix(in, out);\n", prefix);
    fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
    fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
    fprintf(f, "    wire [%d:0] total;\n", WORD_BITS-1);
    fprintf(f, "    assign total = 0");
    for (int i = 0; i < STATE_SIZE; i++)
        fprintf(f, " ^ in[%d:%d]", WORD_BITS*(i+1)-1, WORD_BITS*i);
    fprintf(f, ";\n");
    for (int i = 0; i < STATE_SIZE; i++)
        fprintf(f, "    assign out[%d:%d] = in[%d:%d] ^ total ^ (total >> 32);\n",
                WORD_BITS*(i+1)-1, WORD_BITS*i, WORD_BITS*(i+1)-1, WORD_BITS*i);
    fprintf(f, "endmodule\n\n");

    // s-box
    GenerateSboxes(Sbox1, false, prefix, "small", f);
    GenerateSboxes(Sbox2, true, prefix, "large", f);    
    {
        fprintf(f, "module %sapply_sboxes(clk, in, out);\n", prefix);
        fprintf(f, "    input clk;\n");
        fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
        fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
        int smallSboxIndex = 0;
        int pos = 0;
        int sboxId = 0;
        for (int i = 0; i < STATE_SIZE; i++)
        {
            int largeSboxIndex = i;
            int pairPos, pairNext;
            for (int j = 0; j < SMALL_SBOX_COUNT / STATE_SIZE; j++)
            {
                int next = pos + SMALL_SBOX_WIDTH;
                fprintf(f, "    %ssbox_small%d sbox%dinst(clk, in[%d:%d], out[%d:%d]);\n",
                        prefix, smallSboxIndex, sboxId++, next-1, pos, next-1, pos);
                pos = next;
                next = pos + LARGE_SBOX_WIDTH;
                if (j&1)
                {
                    fprintf(f, "    %ssbox_large%d sbox%dinst(clk, in[%d:%d], in[%d:%d], out[%d:%d], out[%d:%d]);\n",
                            prefix, largeSboxIndex, sboxId++,
                            pairNext-1, pairPos, next-1, pos,
                            pairNext-1, pairPos, next-1, pos);
                }
                else
                {
                    pairPos = pos;
                    pairNext = next;
                }
                pos = next;
                smallSboxIndex++;
            }
        }
        fprintf(f, "endmodule\n\n");
    }
    
    // p-box
    for (int i = 0; i < 2; i++)
    {
        fprintf(f, "module %sapply_pbox%d(in, out);\n", prefix, i);
        fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
        fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
        const Pbox& pbox = Permutation[i];
        int perm[DIGEST_BITS];
        for (int j = 0; j < DIGEST_BITS; j++)
        {
            int word = j / WORD_BITS;
            int bit = j % WORD_BITS;
            for (int r = 0; r < PBOX_SUBROUNDS; r++)
            {
                // masked swap
                if ((pbox.mask[r][word/2] >> bit) & 1)
                    word ^= 1;
                if (r < PBOX_SUBROUNDS-1)
                {
                    // word shuffle
                    word = word * PBOX_M % STATE_SIZE;
                    // rotation
                    if (!(word & 1))
                        bit = (bit + pbox.rotation[r][word/2]) % WORD_BITS;
                }
            }
            fprintf(f, "    assign out[%d] = in[%d];\n", word*WORD_BITS + bit, j);
        }
        fprintf(f, "endmodule\n\n");
    }
    
    // rotations
    fprintf(f, "module %srotation_helper(in, out);\n", prefix);
    fprintf(f, "    input [%d:0] in;\n", WORD_BITS-1);
    fprintf(f, "    output [%d:0] out;\n", WORD_BITS-1);
    fprintf(f, "    assign out = ");
    for (int i = 0; i < ROTATION_COUNT; i++)
    {
        if (i != 0)
            fprintf(f, " ^ ");
        fprintf(f, "{in[%d:%d], in[%d:%d]}", WORD_BITS-1-Rotations[i], 0, WORD_BITS-1, WORD_BITS-Rotations[i]);
    }
    fprintf(f, ";\n");
    fprintf(f, "endmodule\n\n");
    fprintf(f, "module %sapply_rotations(in, out);\n", prefix);
    fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
    fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
    fprintf(f, "    wire [%d:0] rot;\n", DIGEST_BITS-1);
    for (int i = 0; i < STATE_SIZE; i++)
    {
        fprintf(f, "    %srotation_helper rot%dinst(in[%d:%d], rot[%d:%d]);\n",
                prefix, i, (i+1)*WORD_BITS-1, i*WORD_BITS, (i+1)*WORD_BITS-1, i*WORD_BITS);
    }
    fprintf(f, "    assign out = rot ^ {in[%d:%d], in[%d:%d]};\n",
            WORD_BITS-1, 0, DIGEST_BITS-1, WORD_BITS);
    fprintf(f, "endmodule\n\n");

    // round key    
    fprintf(f, "module %sapply_round_key(key, in, out);\n", prefix);
    fprintf(f, "    input [%d:0] key;\n", STATE_SIZE-1);
    fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
    fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
    for (int i = 0; i < STATE_SIZE; i++)
    {
        int lo = WORD_BITS*i;
        int hi = WORD_BITS*(i+1)-1;
        fprintf(f, "    assign out[%d] = in[%d] ^ key[%d];\n", lo, lo, i);
        fprintf(f, "    assign out[%d:%d] = in[%d:%d];\n", hi, lo+1, hi, lo+1);
    }
    fprintf(f, "endmodule\n\n");

    // full round
    fprintf(f, "module %sfull_round(clk, roundkey, in, out);\n", prefix);
    fprintf(f, "    input clk;\n");
    fprintf(f, "    input [%d:0] roundkey;\n", STATE_SIZE-1);
    fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
    fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
    fprintf(f, "    wire [%d:0] mid[0:3];\n", DIGEST_BITS-1);
    fprintf(f, "    %sapply_pbox0 pbox0inst(in, mid[0]);\n", prefix);
    fprintf(f, "    %sapply_sboxes sboxes(clk, mid[0], mid[1]);\n", prefix);
    fprintf(f, "    %sapply_pbox1 pbox1inst(mid[1], mid[2]);\n", prefix);
    fprintf(f, "    %sapply_rotations rotations(mid[2], mid[3]);\n", prefix);
    fprintf(f, "    %sapply_round_key keys(roundkey, mid[3], out);\n", prefix);
    fprintf(f, "endmodule\n\n");

    // get round key
    if (throughput != 1)
    {
        for (int i = 0; i < unrolling; i++)
        {
            fprintf(f, "module %sget_round_key%d(clk, period, key);\n", prefix, i);
            fprintf(f, "    input clk;\n");
            fprintf(f, "    input [%d:0] period;\n", period_bits-1);
            fprintf(f, "    output [%d:0] key;\n", STATE_SIZE-1);
            fprintf(f, "    reg [%d:0] key;\n", STATE_SIZE-1);
            fprintf(f, "    always @(posedge clk) begin\n");
            fprintf(f, "    case (period)\n");
            for (int j = 0, r = i; r < ROUNDS; j++, r += unrolling)
            {
                fprintf(f, "        %d'h%0*x: key <= %d'h%0*x;\n",
                    NIBBLES(period_bits), j,
                    NIBBLES(STATE_SIZE), RoundKey[r]);
            }
            fprintf(f, "    endcase\n");
            fprintf(f, "    end\n");
            fprintf(f, "endmodule\n\n");
        }
    }

    // encrypt loop
    fprintf(f, "module %sencrypt_loop(clk, in, read, out, write);\n", prefix);
    fprintf(f, "    input clk;\n");
    fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
    fprintf(f, "    input read;\n");
    fprintf(f, "    output reg [%d:0] out;\n", DIGEST_BITS-1);
    fprintf(f, "    output write;\n");
    fprintf(f, "    reg [%d:0] state[%d:0];\n", DIGEST_BITS-1, unrolling+extra_delay-1);
    fprintf(f, "    wire [%d:0] next[%d:0];\n", DIGEST_BITS-1, unrolling+extra_delay-1);
    for (int i = 1; i < unrolling+extra_delay; i++)
        fprintf(f, "    always @(posedge clk) state[%d] <= next[%d];\n", i, i-1);
    for (int i = 0; i < extra_delay; i++)
        fprintf(f, "    assign next[%d] = state[%d];\n", i+unrolling, i+unrolling);
    if (throughput != 1)
    {
        fprintf(f, "    wire [%d:0] roundkey[%d:0];\n", STATE_SIZE-1, unrolling-1);
        fprintf(f, "    reg [%d:0] period[%d:0];\n", period_bits-1, 2*unrolling+extra_delay-1);
        for (int i = 1; i < 2*unrolling+extra_delay; i++)
            fprintf(f, "    always @(posedge clk) period[%d] <= period[%d];\n", i, i-1);
        for (int i = 0; i < unrolling; i++)
        {
            fprintf(f, "    %sget_round_key%d get_key%d(clk, period[%d], roundkey[%d]);\n", prefix, i, i, 2*i, i);
            fprintf(f, "    %sfull_round round%d(clk, roundkey[%d], state[%d], next[%d]);\n", prefix, i, i, i, i);
        }
        fprintf(f, "    always @(posedge clk) begin\n");
        fprintf(f, "        if (read)\n");
        fprintf(f, "        begin\n");
        fprintf(f, "            period[0] <= 0;\n");
        fprintf(f, "            state[0] <= in;\n");
        fprintf(f, "        end\n");
        fprintf(f, "        else\n");
        fprintf(f, "        begin\n");
        fprintf(f, "            period[0] <= period[%d]+1;\n", 2*unrolling+extra_delay-1);
        fprintf(f, "            state[0] <= next[%d];\n", unrolling+extra_delay-1);
        fprintf(f, "        end\n");
        fprintf(f, "        out <= next[%d];\n", (ROUNDS-1) % unrolling);
        fprintf(f, "    end\n");
    }
    else
    {
        for (int i = 0; i < unrolling; i++)
        {
            fprintf(f, "    %sfull_round round%d(clk, %d'h%0*x, state[%d], next[%d]);\n",
                    prefix, i, NIBBLES(STATE_SIZE), RoundKey[i], i, i);
        }
        fprintf(f, "    always @(posedge clk) begin\n");
        fprintf(f, "        state[0] <= in;\n");
        fprintf(f, "        out <= next[%d];\n", ROUNDS-1);
        fprintf(f, "    end\n");
    }
    fprintf(f, "    reg [%d:0] progress;\n", latency-1);
    fprintf(f, "    initial progress = %d'h0;\n", latency);
    fprintf(f, "    always @(posedge clk) progress[0] <= read;\n");
    for (int i = 1; i < latency; i++)
        fprintf(f, "    always @(posedge clk) progress[%d] <= progress[%d];\n", i, i-1);
    fprintf(f, "    assign write = progress[%d];\n", latency-1);
    fprintf(f, "endmodule\n\n");
    
    // encrypt
    fprintf(f, "module %sencrypt(clk, in, read, out, write);\n", prefix);
    fprintf(f, "    localparam THROUGHPUT = %d;\n", throughput);
    fprintf(f, "    input clk;\n");
    fprintf(f, "    input [%d:0] in;\n", DIGEST_BITS-1);
    fprintf(f, "    input read;\n");
    fprintf(f, "    output [%d:0] out;\n", DIGEST_BITS-1);
    fprintf(f, "    output write;\n");
    fprintf(f, "    reg [1:0] progress;\n");
    fprintf(f, "    initial progress = 2'h0;\n");
    fprintf(f, "    reg [639:0] state[1:0];\n");
    fprintf(f, "    wire [639:0] next;\n");
    fprintf(f, "    %spre_mix premixer(state[0], next);\n", prefix);
    fprintf(f, "    %sencrypt_loop crypter(clk, state[1], progress[1], out, write);\n", prefix);
    fprintf(f, "    always @(posedge clk) begin\n");
    fprintf(f, "        progress[0] <= read;\n");
    fprintf(f, "        progress[1] <= progress[0];\n");
    fprintf(f, "        state[0] <= in;\n");
    fprintf(f, "        state[1] <= next;\n");
    fprintf(f, "    end\n");
    fprintf(f, "endmodule\n");
}

int usage(const char* arg0, const char* message)
{
    fprintf(stderr, "%s", message);
    fprintf(stderr, "Usage: %s <seed> <throughput> [prefix]\n", arg0);
    return 1;
}

int main(int argc, char* argv[])
{
    uint32_t key = 0;
    uint32_t throughput = 0;
    const char* prefix = NULL;
    if (argc < 3 || argc > 4)
        return usage(argv[0], "Incorrect number of agruments");
    key = strtoul(argv[1], NULL, 0);
    throughput = strtoul(argv[2], NULL, 0);
    if (throughput == 0)
        return usage(argv[0], "Throughput cannot be 0");
    if (argc == 4)
        prefix = argv[3];
    OdoVerilog(key).Generate(throughput, prefix);
}
