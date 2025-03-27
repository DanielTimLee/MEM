module l2_cache (
    input wire clk,
    input wire reset,
    input wire [31:0] addr,
    input wire request,
    input wire write_en,
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
//    localparam NUM_SETS = 1024;         // 1024 sets
    localparam NUM_SETS = 8;         // was 1024 sets
    localparam ASSOCIATIVITY = 4;       // 4-way associative
    localparam BLOCK_SIZE = 64;         // 64-byte blocks
    localparam TAG_WIDTH = 18;          // 32 - 14 (10 index + 4 offset) = 18 bits

    // Cache arrays
    reg [TAG_WIDTH-1:0] tags [0:NUM_SETS*ASSOCIATIVITY-1];  // 4096 tags
    reg [BLOCK_SIZE*8-1:0] data [0:NUM_SETS*ASSOCIATIVITY-1]; // 4096 blocks
    reg valid [0:NUM_SETS*ASSOCIATIVITY-1];
    reg dirty [0:NUM_SETS*ASSOCIATIVITY-1];

    // Address breakdown
    wire [9:0] index = addr[13:4];      // Index for 1024 sets
    wire [3:0] offset = addr[3:0];      // Word offset within 64B block
    wire [17:0] tag = addr[31:14];      // Physical tag

    typedef enum { IDLE, CHECK, MISS_READ, MISS_WRITEBACK } state_t;
    state_t state;

    reg [1:0] replace_way;
    reg [3:0] ram_count;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            ram_read_en <= 0;
            ram_write_en <= 0;
            replace_way <= 0;
            ram_count <= 0;
            for (integer i = 0; i < NUM_SETS*ASSOCIATIVITY; i = i + 1) begin
                valid[i] <= 0;
                dirty[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (request) state <= CHECK;
                end
                CHECK: begin
                    integer i;
                    done <= 0;
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (valid[index*ASSOCIATIVITY + i] && tags[index*ASSOCIATIVITY + i] == tag) begin
                            if (!write_en) data_out <= data[index*ASSOCIATIVITY + i];
                            else begin
                                data[index*ASSOCIATIVITY + i] <= write_data;
                                dirty[index*ASSOCIATIVITY + i] <= 1;
                            end
                            done <= 1;
                            state <= IDLE;
                        end
                    end
                    if (!done) begin
                        replace_way <= replace_way + 1;
                        ram_addr <= {addr[31:4], 4'b0};
                        if (valid[{index, replace_way}] && dirty[{index, replace_way}]) begin
                            ram_data_in <= data[{index, replace_way}][ram_count*32 +: 32];
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
                        data[{index, replace_way}][ram_count*32 +: 32] <= ram_data;
                        ram_addr <= ram_addr + 1;
                        ram_count <= ram_count + 1;
                    end else begin
                        ram_read_en <= 0;
                        tags[{index, replace_way}] <= tag;
                        valid[{index, replace_way}] <= 1;
                        dirty[{index, replace_way}] <= 0;
                        data_out <= data[{index, replace_way}];
                        done <= 1;
                        state <= IDLE;
                    end
                end
                MISS_WRITEBACK: begin
                    if (ram_count < 16) begin
                        ram_data_in <= data[{index, replace_way}][ram_count*32 +: 32];
                        ram_addr <= ram_addr + 1;
                        ram_count <= ram_count + 1;
                    end else begin
                        ram_write_en <= 0;
                        ram_read_en <= 1;
                        ram_addr <= {addr[31:4], 4'b0};
                        ram_count <= 0;
                        state <= MISS_READ;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule