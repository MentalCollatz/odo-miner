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

module cmp_256(clk, in, read, target, out, write);
    input clk;
    input [255:0] in;
    input read;
    input [255:0] target;
    output reg out;
    output reg write;
    
    reg [15:0] greater, less;
    reg progress;
    initial progress = 0;
    initial write = 0;
    
    genvar i;
    generate
    for (i = 0; i < 16; i = i+1)
    begin : loop
        always @(posedge clk)
        begin
            greater[i] <= (in[16*i+15:16*i] > target[16*i+15:16*i]);
            less[i] <= (in[16*i+15:16*i] < target[16*i+15:16*i]);
        end
    end
    endgenerate
    
    always @(posedge clk)
    begin
        out <= (greater < less);
        progress <= read;
        write <= progress;
    end
endmodule

module odo_keccak(clk, in, read, target, out, write);
    input clk;
    input [639:0] in;
    input read;
    input [255:0] target;
    output out;
    output write;

    wire [639:0] midstate;
    wire midread;
    wire [255:0] pow_hash;
    wire has_hash;
    
    odo_encrypt crypt(clk, in, read, midstate, midread);
    keccak_hasher #(640, `THROUGHPUT) hash(clk, midstate, midread, pow_hash, has_hash);
    cmp_256 compare(clk, pow_hash, has_hash, target, out, write);
endmodule

module miner(clk, header, target, nonce);
    parameter INONCE = 0; // for testing

    input clk;
    input [607:0] header;
    input [255:0] target;
    output reg [31:0] nonce;
    
    reg [31:0] nonce_in;
    reg [31:0] nonce_out;
    initial nonce_in = INONCE;
    initial nonce_out = INONCE;
    
    reg [6:0] counter;
    reg advance;
    initial counter = `THROUGHPUT-1;
    initial advance = 0;
    
    wire res;
    wire has_res;
    
    odo_keccak worker(clk, {nonce_in, header}, advance, target, res, has_res);
    
    always @(posedge clk)
    begin
        if (counter == `THROUGHPUT-1)
        begin
            counter <= 0;
            advance <= 1;
        end
        else
        begin
            counter <= counter + 1;
            advance <= 0;
        end
        if (advance)
            nonce_in <= nonce_in + 1;
        if (has_res)
        begin
            if (res)
                nonce <= nonce_out;
            nonce_out <= nonce_out + 1;
        end
    end
endmodule

module pad_nonce(clk, in, out);
    input clk;
    input [31:0] in;
    output reg [43:0] out;

    wire [11:0] checksum;
    crc12 cksum(in, checksum);

    always @(posedge clk)
    begin
        out <= { checksum, in };
    end
endmodule

module miner_top(osc_clk);
    input osc_clk;
    
    wire [607:0] header;
    // Altera docs suggest maximum source width is 256, but it actually seems
    // to go higher than that (but not up to 608). So split the header into 2
    // separate probe instances.
    source #(288, "WRK1") src1(header[287:0]);
    source #(320, "WRK2") src2(header[607:288]);
    
    // A full 256 bits for this may be a bit overkill
    wire [255:0] target;
    source #(256, "TRGT") src3(target);
    
    wire [31:0] nonce;
    wire [43:0] padded_nonce;
    probe #(44, "GNON") probe_nonce(padded_nonce);
    
    wire [31:0] seed = `ODOKEY;
    probe #(32, "SEED") probe_seed(seed);
    
    wire miner_clk;
    pll main_pll(osc_clk, miner_clk);

    miner(miner_clk, header, target, nonce);
    pad_nonce(miner_clk, nonce, padded_nonce);
endmodule
    
