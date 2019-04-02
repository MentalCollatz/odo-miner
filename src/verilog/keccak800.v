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

module keccak_next_round(in, out);
    input [7:0] in;
    output [7:0] out;
    
    assign out[0] = in[7];
    assign out[1] = in[0]^ in[4]^ in[5]^ in[6];
    assign out[2] = in[1]^ in[5]^ in[6]^ in[7];
    assign out[3] = in[0]^ in[2]^ in[4]^ in[5]^ in[7];
    assign out[4] = in[0]^ in[1]^ in[3]^ in[4];
    assign out[5] = in[1]^ in[2]^ in[4]^ in[5];
    assign out[6] = in[2]^ in[3]^ in[5]^ in[6];
    assign out[7] = in[3]^ in[4]^ in[6]^ in[7];
endmodule

module keccak_key_expand(in, out);
    input [7:0] in;
    output [31:0] out;
    
    assign out = {in[5], 15'b0, in[4], 7'b0, in[3], 3'b0, in[2], 1'b0, in[1], in[0]};
endmodule

`define IDX32(x) ((x)*(32)) +: 32
`define LANE(x,y) (((x)%5)+5*((y)%5))

module keccak_theta(in, out);
    input [799:0] in;
    output [799:0] out;
    wire [31:0] parity [4:0];
    
    genvar i;
    generate
    for (i = 0; i < 5; i = i+1)
    begin : loop1
        assign parity[i] = in[`IDX32(i)] ^ in[`IDX32(i+5)] ^ in[`IDX32(i+10)] ^ in[`IDX32(i+15)] ^ in[`IDX32(i+20)];
    end
    endgenerate

    generate
    for (i = 0; i < 25; i = i+1)
    begin : loop2
        wire [31:0] tmp = {parity[(i+1)%5][30:0], parity[(i+1)%5][31]};
        assign out[`IDX32(i)] = in[`IDX32(i)] ^ parity[(i+4)%5] ^ tmp;
    end
    endgenerate
endmodule

module keccak_rho(in, out);
    input [799:0] in;
    output [799:0] out;
    
    assign out = {
        in[785:768],in[799:786],
        in[743:736],in[767:744],
        in[706:704],in[735:707],
        in[701:672],in[703:702],
        in[653:640],in[671:654],
        in[631:608],in[639:632],
        in[586:576],in[607:587],
        in[560:544],in[575:561],
        in[530:512],in[543:531],
        in[502:480],in[511:503],
        in[472:448],in[479:473],
        in[422:416],in[447:423],
        in[404:384],in[415:405],
        in[373:352],in[383:374],
        in[348:320],in[351:349],
        in[299:288],in[319:300],
        in[264:256],in[287:265],
        in[249:224],in[255:250],
        in[211:192],in[223:212],
        in[187:160],in[191:188],
        in[132:128],in[159:133],
        in[99:96],in[127:100],
        in[65:64],in[95:66],
        in[62:32],in[63:63],
        in[31:0]
    };
endmodule

module keccak_pi(in, out);
    input [799:0] in;
    output [799:0] out;
    
    genvar x;
    genvar y;
    generate
    for (x = 0; x < 5; x = x+1)
    begin : outer
        for (y = 0; y < 5; y = y+1)
        begin : loop
            assign out[`IDX32(`LANE(0*x+1*y, 2*x+3*y))] = in[`IDX32(`LANE(x, y))];
        end
    end
    endgenerate
endmodule

module keccak_chi(in, out);
    input [799:0] in;
    output [799:0] out;
    
    genvar i;
    generate
    for (i = 0; i < 25; i = i+1)
    begin : loop
        localparam i1 = i-(i%5)+((i+1)%5);
        localparam i2 = i-(i%5)+((i+2)%5);
        assign out[`IDX32(i)] = in[`IDX32(i)] ^ ((~in[`IDX32(i1)]) & in[`IDX32(i2)]);
    end
    endgenerate
endmodule

module keccak_iota(in, roundkey, out);
    input [799:0] in;
    input [7:0] roundkey;
    output [799:0] out;
    
    wire [31:0] expanded;
    keccak_key_expand re(roundkey, expanded);
    assign out = {in[799:32], in[31:0] ^ expanded};
endmodule    

module keccak_buffer(clk, statein, keyin, stateout, keyout);
    input clk;
    input [799:0] statein;
    input [7:0] keyin;
    output reg [799:0] stateout;
    output reg [7:0] keyout;
    
    always @(posedge clk)
    begin
        stateout <= statein;
        keyout <= keyin;
    end
endmodule

module keccak_round(clk, in, out);
    input clk;
    input [807:0] in;
    output [807:0] out;
    
    wire [799:0] midstate [6:0];
    wire [7:0] roundkey [2:0];
    
    reg [799:0] statebuf;
    reg [7:0] keybuf;
    
    assign midstate[0] = in[799:0];
    assign roundkey[0] = in[807:800];
    
    keccak_theta  theta (midstate[0], midstate[1]);
    keccak_buffer buffer(clk, midstate[1], roundkey[0], midstate[2], roundkey[1]);
    keccak_rho    rho   (midstate[2], midstate[3]);
    keccak_pi     pi    (midstate[3], midstate[4]);
    keccak_chi    chi   (midstate[4], midstate[5]);
    keccak_iota   iota  (midstate[5], roundkey[1], midstate[6]);
    keccak_next_round next(roundkey[1], roundkey[2]);
    
    assign out = {roundkey[2], midstate[6]};
endmodule

module keccak_padding(in, out);
    parameter WIDTH = 0;
    
    input [WIDTH-1:0] in;
    output [807:0] out;
    
    // 0x35 for 12 rounds
    assign out = {8'h35, {799-WIDTH{1'b0}}, 1'b1, in};
endmodule

module keccak_hasher(clk, in, read, out, write);
    parameter WIDTH = 0; // input width
    parameter THROUGHPUT = 0; // clocks per hash

    localparam ROUNDS = 12;
    localparam UNROLLING = (ROUNDS-1) / THROUGHPUT + 1;
    // Add some extra delay so that gcd(THROUGHPUT, 2*UNROLLING+EXTRA_DELAY)=1
    localparam EXTRA_DELAY = 
        (THROUGHPUT == 3) ? 2 :
        (THROUGHPUT == 10) ? 3 :
        (THROUGHPUT < 12) ? 1 :
        ((THROUGHPUT % 6) == 0) ? 3 :
        ((THROUGHPUT % 6) == 3) ? 2 : 1;
    localparam LATENCY = 2*ROUNDS + ((ROUNDS-1) / UNROLLING) * EXTRA_DELAY + 1;
    
    input clk;
    input [WIDTH-1:0] in;
    input read;
    output reg [255:0] out;
    output write;
    
    reg [807:0] state[UNROLLING+EXTRA_DELAY-1:0];
    wire [807:0] next[UNROLLING+EXTRA_DELAY-1:0];
    
    wire [807:0] padded;
    keccak_padding #(WIDTH) padder(in, padded);
    
    genvar i;
    generate
    for (i = 0; i < UNROLLING; i = i+1)
    begin : loop1
        keccak_round round(clk, state[i], next[i]);
    end
    endgenerate

    generate
    for (i = 0; i < EXTRA_DELAY; i = i+1)
    begin : loop2
        assign next[i+UNROLLING] = state[i+UNROLLING];
    end
    endgenerate
    
    generate
    for (i = 1; i < UNROLLING+EXTRA_DELAY; i = i+1)
    begin : loop3
        always @(posedge clk)
            state[i] <= next[i-1];
    end
    endgenerate
        
    reg [LATENCY-1:0] progress;
    initial progress = {LATENCY{1'h0}};
    assign write = progress[LATENCY-1];
    
    generate
    for (i = 1; i < LATENCY; i = i+1)
    begin : loop4
        always @(posedge clk)
            progress[i] <= progress[i-1];
    end
    endgenerate

    always @(posedge clk)
    begin
        if (THROUGHPUT == 1 || read)
            state[0] <= padded;
        else
            state[0] <= next[UNROLLING+EXTRA_DELAY-1];
        
        progress[0] <= read;
        
        out <= next[(ROUNDS-1) % UNROLLING][255:0];
    end
endmodule

