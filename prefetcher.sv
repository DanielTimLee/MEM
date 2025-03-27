module prefetcher (
    input wire clk,
    input wire reset,
    // L1 ICache interface
    input wire icache_miss,
    input wire [31:0] icache_addr,
    // L1 DCache interface
    input wire dcache_miss,
    input wire [31:0] dcache_addr,
    // MMU/TLB interface
    output reg [31:0] mmu_addr,
    output reg mmu_request,
    input wire [31:0] mmu_paddr,
    input wire mmu_done,
    // L2 Cache interface
    output reg [31:0] l2_addr,
    output reg l2_request,
    input wire [255:0] l2_data,
    input wire l2_done,
    // L1 Cache prefetch outputs
    output reg [31:0] icache_prefetch_addr,
    output reg [255:0] icache_prefetch_data,
    output reg icache_prefetch_valid,
    output reg [31:0] dcache_prefetch_addr,
    output reg [255:0] dcache_prefetch_data,
    output reg dcache_prefetch_valid
);
    // Parameters
    localparam BLOCK_SIZE = 32; // 32-byte blocks

    // Registers
    reg [31:0] prefetch_addr;
    reg is_icache;

    typedef enum { IDLE, DETECT, TRANSLATE, FETCH, STORE } state_t;
    state_t state;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            mmu_request <= 0;
            l2_request <= 0;
            icache_prefetch_valid <= 0;
            dcache_prefetch_valid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    icache_prefetch_valid <= 0;
                    dcache_prefetch_valid <= 0;
                    if (icache_miss || dcache_miss) begin
                        state <= DETECT;
                        is_icache <= icache_miss;
                        prefetch_addr <= (icache_miss ? icache_addr : dcache_addr) + BLOCK_SIZE; // Next block
                    end
                end
                DETECT: begin
                    mmu_addr <= prefetch_addr;
                    mmu_request <= 1;
                    state <= TRANSLATE;
                end
                TRANSLATE: begin
                    if (mmu_done) begin
                        mmu_request <= 0;
                        l2_addr <= {mmu_paddr[31:5], 5'b0}; // Align to 32B
                        l2_request <= 1;
                        state <= FETCH;
                    end
                end
                FETCH: begin
                    if (l2_done) begin
                        l2_request <= 0;
                        if (is_icache) begin
                            icache_prefetch_addr <= prefetch_addr;
                            icache_prefetch_data <= l2_data;
                            icache_prefetch_valid <= 1;
                        end else begin
                            dcache_prefetch_addr <= prefetch_addr;
                            dcache_prefetch_data <= l2_data;
                            dcache_prefetch_valid <= 1;
                        end
                        state <= STORE;
                    end
                end
                STORE: begin
                    icache_prefetch_valid <= 0;
                    dcache_prefetch_valid <= 0;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule