module iommu (
    input wire clk,
    input wire reset,
    input wire [31:0] daddr,            // Device virtual address (DVA)
    input wire translate_request,
    input wire write_en,                // Device write request
    input wire [31:0] write_data,       // 32-bit data from device
    output reg [31:0] paddr,            // Physical address
    output reg [31:0] data_out,         // Data for read
    output reg translation_done,
    output reg fault,
    // TLB interface
    output reg tlb_query_valid,
    output reg [31:0] tlb_query_vaddr,
    input wire [31:0] tlb_paddr,
    input wire tlb_hit,
    output reg tlb_update_valid,
    output reg [31:0] tlb_update_vaddr,
    output reg [31:0] tlb_update_paddr,
    // L2 Cache interface (via DCache-like path)
    output reg [31:0] l2_addr,
    output reg l2_request,
    output reg [255:0] l2_write_data,   // 32-byte block
    output reg l2_write_en,
    input wire [255:0] l2_data,
    input wire l2_done,
    // RAM interface (for page table walks)
    output reg [29:0] ram_read_address,
    output reg ram_read_en,
    input wire [31:0] ram_data_out
);
    // Define states
    typedef enum { IDLE, TLB_CHECK, READ_PDE, WAIT_PDE, CHECK_PDE, READ_PTE, WAIT_PTE, CHECK_PTE, ACCESS_L2, DONE } state_t;
    state_t state;

    // Registers
    reg [31:0] daddr_reg;
    reg [29:0] pde_address;
    reg [31:0] pde_data;
    reg [31:0] page_table_physical_address;
    reg [29:0] pte_address;
    reg [31:0] pte_data;
    reg [31:0] paddr_reg;
    reg fault_reg;
    reg translation_done_reg;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            daddr_reg <= 0;
            pde_address <= 0;
            pde_data <= 0;
            page_table_physical_address <= 0;
            pte_address <= 0;
            pte_data <= 0;
            paddr_reg <= 0;
            fault_reg <= 0;
            translation_done_reg <= 0;
            tlb_query_valid <= 0;
            tlb_update_valid <= 0;
            l2_request <= 0;
            l2_write_en <= 0;
            ram_read_en <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (translate_request) begin
                        daddr_reg <= daddr;
                        tlb_query_vaddr <= daddr;
                        tlb_query_valid <= 1;
                        state <= TLB_CHECK;
                    end
                    translation_done_reg <= 0;
                    fault_reg <= 0;
                end
                TLB_CHECK: begin
                    tlb_query_valid <= 0;
                    if (tlb_hit) begin
                        paddr_reg <= tlb_paddr;
                        l2_addr <= {tlb_paddr[31:5], 5'b0}; // 32-byte aligned
                        l2_request <= 1;
                        l2_write_en <= write_en;
                        if (write_en) l2_write_data <= {224'b0, write_data};
                        state <= ACCESS_L2;
                    end else begin
                        pde_address <= daddr[31:22]; // Page directory index
                        state <= READ_PDE;
                    end
                end
                READ_PDE: begin
                    ram_read_address <= pde_address;
                    ram_read_en <= 1;
                    state <= WAIT_PDE;
                end
                WAIT_PDE: begin
                    ram_read_en <= 0;
                    pde_data <= ram_data_out;
                    state <= CHECK_PDE;
                end
                CHECK_PDE: begin
                    if (!pde_data[0]) begin
                        fault_reg <= 1;
                        state <= DONE;
                    end else begin
                        page_table_physical_address <= pde_data & 32'hFFFFF000;
                        pte_address <= (page_table_physical_address >> 2) + daddr_reg[21:12];
                        state <= READ_PTE;
                    end
                end
                READ_PTE: begin
                    ram_read_address <= pte_address;
                    ram_read_en <= 1;
                    state <= WAIT_PTE;
                end
                WAIT_PTE: begin
                    ram_read_en <= 0;
                    pte_data <= ram_data_out;
                    state <= CHECK_PTE;
                end
                CHECK_PTE: begin
                    if (!pte_data[0]) begin
                        fault_reg <= 1;
                        state <= DONE;
                    end else begin
                        paddr_reg <= (pte_data & 32'hFFFFF000) | (daddr_reg & 32'hFFF);
                        tlb_update_valid <= 1;
                        tlb_update_vaddr <= daddr_reg;
                        tlb_update_paddr <= paddr_reg;
                        l2_addr <= {paddr_reg[31:5], 5'b0};
                        l2_request <= 1;
                        l2_write_en <= write_en;
                        if (write_en) l2_write_data <= {224'b0, write_data};
                        state <= ACCESS_L2;
                    end
                end
                ACCESS_L2: begin
                    tlb_update_valid <= 0;
                    if (l2_done) begin
                        l2_request <= 0;
                        l2_write_en <= 0;
                        if (!write_en) data_out <= l2_data[daddr_reg[4:2]*32 +: 32];
                        state <= DONE;
                    end
                end
                DONE: begin
                    translation_done_reg <= 1;
                    if (!translate_request) begin
                        state <= IDLE;
                        translation_done_reg <= 0;
                        fault_reg <= 0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    assign paddr = paddr_reg;
    assign translation_done = translation_done_reg;
    assign fault = fault_reg;
endmodule