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
    probe #(32, "GNON") probe_nonce(nonce);
    
    wire [31:0] seed = `ODOKEY;
    probe #(32, "SEED") probe_seed(seed);
    
    wire miner_clk;
    pll main_pll(osc_clk, miner_clk);

    miner(miner_clk, header, target, nonce);
endmodule
    
