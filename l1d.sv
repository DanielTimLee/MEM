module l1_dcache (
    input wire clk,
    input wire reset,
    input wire [31:0] addr,         // Virtual address
    input wire read_en,
    input wire write_en,
    input wire [31:0] write_data,
    output reg [31:0] data_out,
    output reg hit,
    output reg miss,
    // TLB interface
    output reg [31:0] tlb_query_vaddr,
    output reg tlb_query_valid,
    input wire [31:0] tlb_paddr,
    input wire tlb_hit,
    // MMU interface
    output reg [31:0] mmu_addr,
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
//    localparam NUM_LINES = 512;     // 16KB / 32B = 512 lines
    localparam NUM_LINES = 8;     // was 512 lines
    localparam BLOCK_SIZE = 32;     // 32-byte blocks
    localparam TAG_WIDTH = 20;      // Physical tags
    localparam ENTRY_WIDTH = TAG_WIDTH + BLOCK_SIZE*8 + 2;  // 20 + 256 + 1 + 1 = 278 bits

    // RAM array for cache
    reg [ENTRY_WIDTH-1:0] cache [0:NUM_LINES-1];

    wire [8:0] index = addr[13:5];  // Virtual index
    wire [4:0] offset = addr[4:0];
    wire [19:0] phys_tag = tlb_paddr[31:12];
    wire [8:0] prefetch_index = prefetch_addr[13:5];

    // Cached values for combinational lookup
    reg [19:0] cached_tag;
    reg [255:0] cached_data;
    reg cached_valid;
    reg cached_dirty;

    // State machine
    typedef enum { IDLE, LOOKUP, TLB_MISS, FETCH_L2, WRITEBACK } state_t;
    state_t state;

    reg [31:0] addr_reg;
    reg [255:0] new_data;

    // Combinational read for BRAM inference
    always @(posedge clk) begin
        if (reset) begin
            cached_tag <= 0;
            cached_data <= 0;
            cached_valid <= 0;
            cached_dirty <= 0;
        end else begin
            cached_tag <= cache[index][ENTRY_WIDTH-1:ENTRY_WIDTH-TAG_WIDTH];
            cached_data <= cache[index][BLOCK_SIZE*8+1:2];
            cached_valid <= cache[index][1];
            cached_dirty <= cache[index][0];
        end
    end

    // Write logic (single write per cycle)
    always @(posedge clk) begin
        if (reset) begin
            for (integer i = 0; i < NUM_LINES; i = i + 1) cache[i] <= 0;
        end else if (prefetch_valid) begin
            cache[prefetch_index] <= {prefetch_addr[31:12], prefetch_data, 1'b1, 1'b0};
        end else if (state == LOOKUP && hit && write_en) begin
            cache[index] <= {phys_tag, new_data, 1'b1, 1'b1};
        end else if (state == FETCH_L2 && l2_done) begin
            cache[index] <= {mmu_paddr[31:12], new_data, 1'b1, write_en};
        end
    end

    // Control logic
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            hit <= 0;
            miss <= 0;
            tlb_query_valid <= 0;
            mmu_request <= 0;
            l2_request <= 0;
            l2_write_en <= 0;
            data_out <= 0;
            new_data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (read_en || write_en) begin
                        addr_reg <= addr;
                        tlb_query_vaddr <= addr;
                        tlb_query_valid <= 1;
                        state <= LOOKUP;
                    end
                end
                LOOKUP: begin
                    tlb_query_valid <= 0;
                    if (cached_valid && cached_tag == phys_tag && tlb_hit) begin
                        hit <= 1;
                        miss <= 0;
                        if (read_en) begin
                            data_out <= cached_data[offset*8 +: 32];
                            new_data <= cached_data;
                        end else begin
                            new_data <= cached_data;
                            new_data[offset*8 +: 32] <= write_data;
                        end
                        state <= IDLE;
                    end else begin
                        hit <= 0;
                        miss <= 1;
                        mmu_addr <= addr_reg;
                        mmu_request <= 1;
                        state <= TLB_MISS;
                    end
                end
                TLB_MISS: begin
                    if (mmu_done) begin
                        mmu_request <= 0;
                        l2_addr <= {mmu_paddr[31:5], 5'b0};
                        if (cached_valid && cached_dirty) begin
                            l2_write_data <= cached_data;
                            l2_write_en <= 1;
                            l2_request <= 1;
                            state <= WRITEBACK;
                        end else begin
                            l2_request <= 1;
                            state <= FETCH_L2;
                        end
                    end
                end
                FETCH_L2: begin
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
                end
                WRITEBACK: begin
                    if (l2_done) begin
                        l2_write_en <= 0;
                        l2_request <= 0;
                        l2_request <= 1;
                        state <= FETCH_L2;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule