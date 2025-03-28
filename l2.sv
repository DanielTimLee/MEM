module l2_cache (
    input wire clk, reset,
    input wire request,
    input wire write_en,
    input wire [31:0] paddr,
    input wire [511:0] write_data,
    output reg [511:0] data_out,
    output reg done,
    // RAM interface
    output reg [29:0] ram_addr,
    output reg ram_read_en,
    output reg ram_write_en,
    output reg [31:0] ram_data_in,
    input wire [31:0] ram_data
);
    // Cache parameters
//    localparam SETS = 1024;         // 1024 sets
    localparam SETS = 8;         // was 1024 sets
    localparam ASSOCIATIVITY = 4;       // 4-way associative
    localparam LINES = SETS * ASSOCIATIVITY;
    
    localparam BLOCK_SIZE = 64;         // 64-byte blocks
    localparam TAG_WIDTH = 18;          // 32 - 14 (10 index + 4 offset) = 18 bits
    localparam VALID_BIT = 1;
    localparam DIRTY_BIT = 1;

    localparam WIDTH = TAG_WIDTH + BLOCK_SIZE*8 + VALID_BIT + DIRTY_BIT;  // 18 + 512 + 1 + 1 = 532 bits

    reg [WIDTH-1:0] cache [0:LINES-1];

    // Address breakdown
    wire [17:0] tag = paddr[31:14];      // Physical tag
    wire [9:0]  idx = paddr[13:4];      // 10 bit for 1024 sets
    wire [3:0]  offset = paddr[3:0];      // Word offset within 64B block
    wire [11:0] base_idx  = {idx, 2'b00};

    `define VALID(entry)                entry[1]
    `define DIRTY(entry)                entry[0]
    `define DATA(entry)                 entry[BLOCK_SIZE*8 + 1:2]
    `define DATA_SLICE(entry, i)        entry[BLOCK_SIZE*8 + 1 - (i)*32 -: 32]
    `define TAG(entry)                  entry[531:514]
    `define TAG_MATCH(entry, tag)       (entry[531:514] == tag)
    `define FOR_EACH_CNT(i, start, N)   for (int i = start; i < start + N; i = i + 1)

    typedef enum { IDLE, CHECK, MISS_READ, MISS_WRITEBACK } state_t;
    state_t state;

    reg [1:0] replace_way;
    reg [11:0] replace_idx;
    reg [3:0] ram_count;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            ram_read_en <= 0;
            ram_write_en <= 0;
            replace_way <= 0;
            ram_count <= 0;
            `FOR_EACH_CNT(i, 0, LINES)
                cache[i] <= 0;
                
        end else begin
            case (state)
                IDLE:
                    if (request)
                        state <= CHECK;
                
                CHECK: begin
                    done <= 0;
                    `FOR_EACH_CNT(IDX, base_idx, ASSOCIATIVITY)
                        if (`VALID(cache[IDX]) && `TAG_MATCH(cache[IDX], tag)) begin
                            if (!write_en)
                                data_out <= `DATA(cache[IDX]);
                            else begin
                                `DATA(cache[IDX]) <= write_data;
                                `DIRTY(cache[IDX]) <= 1;
                            end
                            done <= 1;
                            state <= IDLE;
                        end

                    if (!done) begin
                        replace_way <= replace_way + 1;
                        replace_idx = base_idx + replace_way;

                        ram_addr <= {paddr[31:4], 4'b0};
                        if (`VALID(cache[replace_idx]) && `DIRTY(cache[replace_idx])) begin
                            ram_data_in <= `DATA_SLICE(cache[replace_idx], ram_count);
                            ram_write_en <= 1;
                            ram_count <= 0;
                            state <= MISS_WRITEBACK;
                        end else begin
                            ram_read_en <= 1;
                            ram_count <= 0;
                            state <= MISS_READ;
                        end
                    end
                end
                MISS_READ: begin
                    if (ram_count < 16) begin
                        `DATA_SLICE(cache[replace_idx], ram_count) <= ram_data;
                        ram_addr <= ram_addr + 1;
                        ram_count <= ram_count + 1;
                    end else begin
                        ram_read_en <= 0;
                        `TAG(cache[replace_idx]) <= tag;
                        `VALID(cache[replace_idx]) <= 1;
                        `DIRTY(cache[replace_idx]) <= 0;
                        data_out <= `DATA(cache[replace_idx]);
                        done <= 1;
                        state <= IDLE;
                    end
                end
                MISS_WRITEBACK: begin
                    if (ram_count < 16) begin
                        ram_data_in <= `DATA_SLICE(cache[replace_idx], ram_count);
                        ram_addr <= ram_addr + 1;
                        ram_count <= ram_count + 1;
                    end else begin
                        ram_write_en <= 0;
                        ram_read_en <= 1;
                        ram_addr <= {paddr[31:4], 4'b0};
                        ram_count <= 0;
                        state <= MISS_READ;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule