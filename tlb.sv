module tlb (
    input wire clk, reset,
    input wire [31:0] vaddr,
    output reg [31:0] paddr,
    output reg hit,
    // MMU update interface
    input wire mmu_update_request,
    input wire [31:0] mmu_paddr
);
    // TLB parameters
    localparam SETS = 64;               // 64 sets
    localparam ASSOCIATIVITY = 4;       // 4-way associative
    localparam LINES = SETS * ASSOCIATIVITY;
    
    localparam TAG_WIDTH = 14;          // 32 - 12 (offset) - 6 (set index) = 14 bits
    localparam PPAGE_WIDTH = 20;        // 32 - 12 (offset) = 20 bits for physical page
    localparam VALID_BIT = 1;
    
    localparam WIDTH = TAG_WIDTH + PPAGE_WIDTH + VALID_BIT; // Tag + Physical Page + Valid bit = 35 bits

    // TLB array
    reg [WIDTH-1:0] tlb [0:LINES-1]; // 256 entries (64 sets * 4 ways)
    
    `define VALID(entry)                entry[0]
    `define TAG_MATCH(entry, tag)       (entry[34:21] == tag)
    `define FOR_EACH_CNT(i, start, N)   for (int i = start; i < start + N; i = i + 1)

    // Extract set index and tag for query
    wire [13:0] tag         = vaddr[31:18];     // 14-bit tag
    wire [5:0]  idx         = vaddr[17:12];     // 6 bits for 64 sets
    wire [7:0]  base_index  = {idx, 2'b00};

    // Extract set index and tag for MMU update
    wire [19:0] ppage_mmu   = mmu_paddr[31:12];
    
    always @(posedge clk) begin
        hit = 0;
        paddr = 32'h0;
        
        if (reset)
            `FOR_EACH_CNT(i, 0, LINES)
                tlb[i] <= 0;
        
        // TLB update - reqeuested by MMU
        else if (mmu_update_request) begin
            reg [7:0] target_idx = base_index;

            // find exact match or last invalid entry
            `FOR_EACH_CNT(IDX, base_index, ASSOCIATIVITY) begin
                if (`VALID(tlb[IDX]) && `TAG_MATCH(tlb[IDX], tag)) begin
                    target_idx = IDX;
                    break;
                end
            
                if (!`VALID(tlb[IDX]))
                    target_idx = IDX;
            end
            tlb[target_idx] <= {tag, ppage_mmu, 1'b1};
        end
        
        // TLB lookup - simultaneously with L1 access (VIPT)
        else
            `FOR_EACH_CNT(IDX, base_index, ASSOCIATIVITY)
                if (`VALID(tlb[IDX]) && `TAG_MATCH(tlb[IDX], tag)) begin
                    hit = 1;
                    paddr = {tlb[IDX][20:1], vaddr[11:0]}; // Physical page + offset
                    break;
                end
    end

endmodule