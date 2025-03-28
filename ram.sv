module ram (
    input wire clk,
    input wire [29:0] addr,         // 30-bit address for 4GB
    input wire read_en,
    input wire write_en,            // Added write enable
    input wire [31:0] data_in,      // Added write data input
    output reg [31:0] data_out      // Read data output
);
    reg [31:0] ram [0:4095];  // RAM array expanded to 4096 entries * 4Byte (16KB = 4 pages)

    `define FOR_EACH_RANGE(i, start, N)   for (int i = start; i < N; i = i + 1)

    always @(posedge clk) begin
        if (write_en) begin
            ram[addr] <= data_in;   // Write data to RAM
        end
        if (read_en) begin
            data_out <= ram[addr];  // Read data from RAM
        end
    end

    // Initialize RAM with page directory and page table for testing
    initial begin
        // Initialize page directory entries (1~1023: NULL)
        // Page directory entry 0: points to page table at physical address 4096 (0x1000), present bit set
        ram[0] = 32'h00001000 | 32'h1;  // Physical address 4096, bits 31-12 = 0x1000        
        `FOR_EACH_RANGE(i, 1, 1024) 
            ram[i] = 32'h0;

        // Initialize page table entries (1025~2047: NULL)
        // Page table at ram[1024] (physical address 4096), entry 0: maps to physical page at address 8192 (0x2000), present bit set
        ram[1024] = 32'h00002000 | 32'h1;  // Physical address 8192, bits 31-12 = 0x2000
        `FOR_EACH_RANGE(i, 1025, 2048)
            ram[i] = 32'h0;

        // Initialize rest of RAM (2048 to 4095) to 0
        `FOR_EACH_RANGE(i, 2048, 4096)
            ram[i] = 32'h0; 
    end

endmodule
