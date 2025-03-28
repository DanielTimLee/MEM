module l1_dcache (
    input wire clk, reset,
    input wire read_en,
    input wire write_en,
    input wire [31:0] vaddr,
    input wire [31:0] write_data,
    output reg [31:0] data_out,
    output reg hit, miss,
    // TLB interface
    input wire [31:0] tlb_paddr,
    input wire tlb_hit,
    // MMU interface
    output reg mmu_request,
    input wire [31:0] mmu_paddr,
    input wire mmu_done,
    // L2 Cache interface
    output reg [31:0] l2_addr,
    output reg l2_request,
    output reg [255:0] l2_write_data,
    output reg l2_write_en,
    input wire [255:0] l2_data,
    input wire l2_done,
    // Prefetcher interface
    input wire [31:0] prefetch_addr,
    input wire [255:0] prefetch_data,
    input wire prefetch_valid
);
//    localparam SETS = 512;            // 16KB / 32B = 512 sets
    localparam SETS = 8;                // 8 sets
    localparam ASSOCIATIVITY = 1;       // 1-way associative
    localparam LINES = SETS * ASSOCIATIVITY;
    
    localparam BLOCK_SIZE = 32;     // 32-byte blocks
    localparam TAG_WIDTH = 20;      // Physical tags
    localparam VALID_BIT = 1;
    localparam DIRTY_BIT = 1;

    localparam WIDTH = TAG_WIDTH + BLOCK_SIZE*8 + VALID_BIT + DIRTY_BIT;  // 20 + 256 + 1 + 1 = 278 bits

    // RAM array for cache
    reg [WIDTH-1:0] cache [0:LINES-1];
    
    // L1 uses VIPT(Virtual Index + Physical Tag) matching
    // 1. Lookup for SET with Virtual Index
    // 2. Match right ENTRY for Physical Tag
    // 3. Fetch value from cache by offset
    wire [8:0]  VIDX           = vaddr[13:5];       // Virtual index (9bit for 2^9 = 512 sets)
    wire [19:0] PTAG           = tlb_paddr[31:12];  // Physical Tag (32 - 12bit[4KB page offset] = 20)
    wire [4:0]  offset         = vaddr[4:0];        // BLOCK_SIZE*8 (4 Byte block * 8 = 256 byte)
                                                    //   = each byte should be accessible
                                                    //   = 256 / 8 bit(1Byte) = 32 (2^5), so here uses 5 bit offset. 
    wire [8:0]  prefetch_VIDX = prefetch_addr[13:5];
    
    // 1. VIDX lookup SET
    reg [19:0]  set_tag     = cache[VIDX][WIDTH-1:WIDTH-TAG_WIDTH];
    reg [255:0] set_data    = cache[VIDX][BLOCK_SIZE*8:1];
    reg         set_valid   = cache[VIDX][1];
    reg         set_dirty   = cache[VIDX][0];

    `define FOR_EACH_RANGE(i, start, N)   for (int i = start; i < N; i = i + 1)

    // State machine
    typedef enum { IDLE, LOOKUP, TLB_MISS, FETCH_L2, WRITEBACK } state_t;
    state_t state;

    reg [31:0] addr_reg;
    reg [255:0] new_data;

    // Write logic (single write per cycle)
    always @(posedge clk) begin
        if (reset)
            `FOR_EACH_RANGE(i, 0, LINES)
                cache[i] <= 0;
                
        else if (prefetch_valid)
            cache[prefetch_VIDX] <= {prefetch_addr[31:12], prefetch_data, 1'b1, 1'b0};
            
        else if (state == LOOKUP && hit && write_en)
            cache[VIDX] <= {PTAG, new_data, 1'b1, 1'b1};
         
        else if (state == FETCH_L2 && l2_done)
            cache[VIDX] <= {mmu_paddr[31:12], new_data, 1'b1, write_en};
    end

    // Control logic
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            hit <= 0;
            miss <= 0;
            mmu_request <= 0;
            l2_request <= 0;
            l2_write_en <= 0;
            data_out <= 0;
            new_data <= 0;
        end else begin
            case (state)
                IDLE:
                    if (read_en || write_en)
                        state <= LOOKUP;

                LOOKUP:
                    if (set_valid && set_tag == PTAG && tlb_hit) begin
                        hit <= 1;
                        miss <= 0;
                        if (read_en) begin
                            data_out <= set_data[offset*8 +: 32];
                            new_data <= set_data;
                        end else begin
                            new_data <= set_data;
                            new_data[offset*8 +: 32] <= write_data;
                        end
                        state <= IDLE;
                    end else begin
                        hit <= 0;
                        miss <= 1;
                        mmu_request <= 1;
                        state <= TLB_MISS;
                    end
                
                TLB_MISS:
                    if (mmu_done) begin
                        mmu_request <= 0;
                        l2_addr <= {mmu_paddr[31:5], 5'b0};
                        if (set_valid && set_dirty) begin
                            l2_write_data <= set_data;
                            l2_write_en <= 1;
                            l2_request <= 1;
                            state <= WRITEBACK;
                        end else begin
                            l2_request <= 1;
                            state <= FETCH_L2;
                        end
                    end

                FETCH_L2:
                    if (l2_done) begin
                        l2_request <= 0;
                        if (write_en) begin
                            new_data <= l2_data;
                            new_data[offset*8 +: 32] <= write_data;
                        end else begin
                            data_out <= l2_data[offset*8 +: 32];
                            new_data <= l2_data;
                        end
                        hit <= 1;
                        miss <= 0;
                        state <= IDLE;
                    end

                WRITEBACK:
                    if (l2_done) begin
                        l2_write_en <= 0;
                        l2_request <= 0;
                        l2_request <= 1;
                        state <= FETCH_L2;
                    end

                default: state <= IDLE;
            endcase
        end
    end
endmodule