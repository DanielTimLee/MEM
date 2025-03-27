module mmu (
    input wire clk,
    input wire reset,
    input wire [31:0] vaddr,            // 32-bit virtual address
    input wire translate_request,
    output wire [31:0] paddr,           // 32-bit physical address
    output wire translation_done,
    output wire fault,
    // TLB update interface
    output reg tlb_update_valid,
    output reg [31:0] tlb_update_vaddr, 
    output reg [31:0] tlb_update_paddr
);
    // Define states for the state machine
    typedef enum { IDLE, READ_PDE, WAIT_PDE, CHECK_PDE, READ_PTE, WAIT_PTE, CHECK_PTE, DONE } state_t;

    state_t state;

    // Registers for intermediate values
    reg [31:0] vaddr_reg;               // Stored virtual address
    reg [29:0] pde_address;             // Page directory entry address (RAM index)
    reg [31:0] pde_data;                // Page directory entry data
    reg [31:0] page_table_physical_address; // Physical address of page table
    reg [29:0] pte_address;             // Page table entry address (RAM index)
    reg [31:0] pte_data;                // Page table entry data
    reg [31:0] paddr_reg;               // Resulting physical address
    reg fault_reg;                      // Fault flag
    reg translation_done_reg;           // Translation completion flag

    // RAM interface
    wire [31:0] ram_data_out;
    reg [29:0] ram_read_address;        // 30-bit address for 4GB RAM
    reg ram_read_en;

    // Instantiate RAM module
    ram ram_inst (
        .clk(clk),
        .addr(ram_read_address),
        .read_en(ram_read_en),
        .data_out(ram_data_out)
    );

    // State machine
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            vaddr_reg <= 0;
            pde_address <= 0;
            pde_data <= 0;
            page_table_physical_address <= 0;
            pte_address <= 0;
            pte_data <= 0;
            paddr_reg <= 0;
            fault_reg <= 0;
            translation_done_reg <= 0;
            ram_read_en <= 0;
            tlb_update_valid <= 0;
            tlb_update_vaddr <= 0;
            tlb_update_paddr <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (translate_request) begin
                        vaddr_reg <= vaddr;
                        pde_address <= vaddr[31:22]; // 10-bit page directory index
                        state <= READ_PDE;
                        tlb_update_valid <= 0; // Reset TLB update signal
                    end
                    translation_done_reg <= 0;
                    fault_reg <= 0;
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
                    if (!pde_data[0]) begin // Check present bit
                        fault_reg <= 1;
                        state <= DONE;
                    end else begin
                        page_table_physical_address <= pde_data & 32'hFFFFF000; // Extract 4KB-aligned physical address
                        // Corrected PTE address calculation: physical address / 4 + page table index
                        pte_address <= (page_table_physical_address >> 2) + vaddr_reg[21:12];
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
                    if (!pte_data[0]) begin // Check present bit
                        fault_reg <= 1;
                        state <= DONE;
                    end else begin
                        paddr_reg <= (pte_data & 32'hFFFFF000) | (vaddr_reg & 32'hFFF); // Combine page frame with offset
                        state <= DONE;
                    end
                end
                DONE: begin
                    translation_done_reg <= 1;
                    if (!fault_reg) begin
                        // Update TLB with successful translation
                        tlb_update_valid <= 1;
                        tlb_update_vaddr <= vaddr_reg;
                        tlb_update_paddr <= paddr_reg;
                    end
                    if (!translate_request) begin
                        state <= IDLE;
                        translation_done_reg <= 0;
                        fault_reg <= 0;
                        tlb_update_valid <= 0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    // Output assignments
    assign paddr = paddr_reg;
    assign translation_done = translation_done_reg;
    assign fault = fault_reg;

endmodule