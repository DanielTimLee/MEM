module tlb (
    input wire clk,
    input wire reset,
    // Query interface
    input wire [31:0] query_vaddr,      // Virtual address to look up
    input wire query_valid,
    output reg [31:0] paddr,            // Physical address output
    output reg hit,                     // Hit signal
    // MMU update interface
    input wire mmu_update_valid,
    input wire [31:0] mmu_vaddr,
    input wire [31:0] mmu_paddr
);
    // TLB parameters
    localparam NUM_SETS = 64;           // 64 sets
    localparam ASSOCIATIVITY = 4;       // 4-way associative
    localparam TAG_WIDTH = 14;          // 32 - 12 (offset) - 6 (set index) = 14 bits
    localparam PPAGE_WIDTH = 20;        // 32 - 12 (offset) = 20 bits for physical page
    localparam ENTRY_WIDTH = TAG_WIDTH + PPAGE_WIDTH + 1; // Tag + Physical Page + Valid bit = 35 bits

    // TLB array
    reg [ENTRY_WIDTH-1:0] tlb [0:NUM_SETS*ASSOCIATIVITY-1]; // 256 entries (64 sets * 4 ways)

    // Extract set index and tag for query
    wire [5:0] set_index_query = query_vaddr[17:12];    // 6 bits for 64 sets
    wire [13:0] tag_query = query_vaddr[31:18];         // 14-bit tag

    // Extract set index and tag for MMU update
    wire [5:0] set_index_mmu = mmu_vaddr[17:12];
    wire [13:0] tag_mmu = mmu_vaddr[31:18];
    wire [19:0] ppage_mmu = mmu_paddr[31:12];

    // For query
    wire [7:0] base_index_query = {set_index_query, 2'b00};
    // For MMU update
    wire [7:0] base_index_mmu   = {set_index_mmu, 2'b00};
    
    // Combinatorial logic for TLB lookup
    always @(*) begin
        if (query_valid) begin
            integer i;
            hit = 0;
            paddr = 32'h0;
            // Calculate base index for the set - base_index_query
            for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                if (tlb[base_index_query + i][0] && (tlb[base_index_query + i][34:21] == tag_query)) begin
                    hit = 1;
                    paddr = {tlb[base_index_query + i][20:1], query_vaddr[11:0]}; // Physical page + offset
                end
            end
        end else begin
            hit = 0;
            paddr = 32'h0;
        end
    end

    // Sequential logic for TLB updates and reset
    always @(posedge clk) begin
        if (reset) begin
            integer i;
            for (i = 0; i < NUM_SETS * ASSOCIATIVITY; i = i + 1) begin
                tlb[i] <= 0; // Clear all entries (valid bit = 0)
            end
        end else begin
            // Handle MMU update 
            if (mmu_update_valid) begin
                integer i;
                reg updated = 0;
                // Check for existing tag match
                for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                    if (!updated && tlb[base_index_mmu + i][0] && (tlb[base_index_mmu + i][34:21] == tag_mmu)) begin
                        tlb[base_index_mmu + i][20:1] <= ppage_mmu; // Update physical page
                        updated = 1;
                    end
                end
                // If no match, find an invalid entry or replace
                if (!updated) begin
                    for (i = 0; i < ASSOCIATIVITY; i = i + 1) begin
                        if (!updated && !tlb[base_index_mmu + i][0]) begin
                            tlb[base_index_mmu + i] <= {tag_mmu, ppage_mmu, 1'b1};
                            updated = 1;
                        end
                    end
                    // If all ways are valid, replace way 0 (simple replacement policy)
                    if (!updated) begin
                        tlb[base_index_mmu] <= {tag_mmu, ppage_mmu, 1'b1};
                    end
                end
            end
        end
    end

endmodule