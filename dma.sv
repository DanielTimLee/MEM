module dma_engine (
    input wire clk,
    input wire reset,
    // CPU configuration interface
    input wire [31:0] src_addr,         // Source virtual address
    input wire [31:0] dst_addr,         // Destination virtual address
    input wire [31:0] size,             // Transfer size in bytes
    input wire start,                   // Start signal from CPU
    output reg done,                    // Transfer complete signal
    output reg error,                   // Error flag (e.g., translation fault)
    // IOMMU interface
    output reg [31:0] iommu_daddr,
    output reg iommu_translate_request,
    output reg iommu_write_en,
    output reg [31:0] iommu_write_data,
    input wire [31:0] iommu_paddr,
    input wire [31:0] iommu_data_out,
    input wire iommu_translation_done,
    input wire iommu_fault
);
    // Parameters
    localparam BURST_SIZE = 32;         // 32-byte bursts

    // Registers
    reg [31:0] src_reg, dst_reg, size_reg;
    reg [31:0] src_paddr, dst_paddr;
    reg [31:0] bytes_transferred;

    typedef enum { IDLE, CONFIG, SRC_TRANSLATE, SRC_READ, DST_TRANSLATE, DST_WRITE, COMPLETE } state_t;
    state_t state;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            error <= 0;
            iommu_translate_request <= 0;
            iommu_write_en <= 0;
            src_reg <= 0;
            dst_reg <= 0;
            size_reg <= 0;
            bytes_transferred <= 0;
            src_paddr <= 0;
            dst_paddr <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        src_reg <= src_addr;
                        dst_reg <= dst_addr;
                        size_reg <= size;
                        bytes_transferred <= 0;
                        state <= CONFIG;
                        done <= 0;
                        error <= 0;
                    end
                end
                CONFIG: begin
                    iommu_daddr <= src_reg + bytes_transferred;
                    iommu_translate_request <= 1;
                    iommu_write_en <= 0;
                    state <= SRC_TRANSLATE;
                end
                SRC_TRANSLATE: begin
                    if (iommu_translation_done) begin
                        iommu_translate_request <= 0;
                        if (iommu_fault) begin
                            error <= 1;
                            state <= COMPLETE;
                        end else begin
                            src_paddr <= iommu_paddr;
                            state <= SRC_READ;
                        end
                    end
                end
                SRC_READ: begin
                    if (iommu_translation_done) begin // Reuses IOMMU read completion
                        iommu_daddr <= dst_reg + bytes_transferred;
                        iommu_translate_request <= 1;
                        iommu_write_en <= 0;
                        state <= DST_TRANSLATE;
                        iommu_write_data <= iommu_data_out; // Store read data
                    end
                end
                DST_TRANSLATE: begin
                    if (iommu_translation_done) begin
                        iommu_translate_request <= 0;
                        if (iommu_fault) begin
                            error <= 1;
                            state <= COMPLETE;
                        end else begin
                            dst_paddr <= iommu_paddr;
                            iommu_write_en <= 1;
                            state <= DST_WRITE;
                        end
                    end
                end
                DST_WRITE: begin
                    if (iommu_translation_done) begin
                        iommu_write_en <= 0;
                        bytes_transferred <= bytes_transferred + BURST_SIZE;
                        if (bytes_transferred >= size_reg) begin
                            state <= COMPLETE;
                        end else begin
                            state <= CONFIG;
                        end
                    end
                end
                COMPLETE: begin
                    done <= 1;
                    if (!start) begin
                        state <= IDLE;
                        done <= 0;
                        error <= 0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule