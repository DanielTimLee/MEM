module memory_system (
    input wire clk,
    input wire reset,
    input wire [31:0] i_addr,
    input wire i_read_en,
    output wire [31:0] i_data,
    output wire i_hit,
    output wire i_miss,
    input wire [31:0] d_addr,
    input wire d_read_en,
    input wire d_write_en,
    input wire [31:0] d_write_data,
    output wire [31:0] d_data,
    output wire d_hit,
    output wire d_miss,
    input wire [31:0] device_addr,
    input wire device_request,
    input wire device_write_en,
    input wire [31:0] device_write_data,
    output wire [31:0] device_data,
    output wire device_done,
    output wire device_fault,
    input wire [31:0] dma_src_addr,
    input wire [31:0] dma_dst_addr,
    input wire [31:0] dma_size,
    input wire dma_start,
    output wire dma_done,
    output wire dma_error
);
    // MMU/TLB wires
    wire [31:0] tlb_paddr, mmu_paddr;
    wire tlb_hit;
    wire mmu_done, mmu_fault;
    wire mmu_tlb_update_valid, iommu_tlb_update_valid;
    wire [31:0] mmu_tlb_update_vaddr, mmu_tlb_update_paddr;
    wire [31:0] iommu_tlb_update_vaddr, iommu_tlb_update_paddr;

    // L1 ICache wires
    wire [31:0] icache_l2_addr;
    wire icache_mmu_request, icache_l2_request;
    wire [255:0] icache_l2_data;

    // L1 DCache wires
    wire [31:0] dcache_l2_addr;
    wire dcache_mmu_request, dcache_l2_request;
    wire [255:0] dcache_l2_data, dcache_l2_write_data;
    wire dcache_l2_write_en;

    // IOMMU wires
    wire [31:0] iommu_l2_addr;
    wire iommu_tlb_query_valid, iommu_l2_request, iommu_l2_write_en;
    wire [31:0] iommu_tlb_query_vaddr;
    wire [255:0] iommu_l2_write_data, iommu_l2_data;
    wire [29:0] iommu_ram_addr;
    wire iommu_ram_read_en;
    wire [31:0] iommu_data_out;
    wire iommu_done, iommu_fault;

    // DMA wires
    wire [31:0] dma_iommu_daddr;
    wire dma_iommu_translate_request, dma_iommu_write_en;
    wire [31:0] dma_iommu_write_data;

    // Prefetcher wires
    wire [31:0] prefetch_mmu_addr, prefetch_l2_addr;
    wire prefetch_mmu_request, prefetch_l2_request;
    wire [255:0] prefetch_l2_data;
    wire [31:0] icache_prefetch_addr, dcache_prefetch_addr;
    wire [255:0] icache_prefetch_data, dcache_prefetch_data;
    wire icache_prefetch_valid, dcache_prefetch_valid;

    // L2 Cache wires
    wire [29:0] l2_ram_addr;
    wire l2_ram_read_en, l2_ram_write_en;
    wire [511:0] l2_ram_write_data;
    wire [31:0] l2_ram_data_in;
    wire [31:0] ram_data;

    // TLB (separate outputs for ICache and DCache)
    tlb tlb_inst (
        .clk(clk), .reset(reset),
        .paddr(tlb_paddr), .hit(tlb_hit),
        .vaddr(i_addr | d_addr | iommu_tlb_query_vaddr),
        .mmu_update_valid(mmu_tlb_update_valid | iommu_tlb_update_valid),
        .mmu_paddr(mmu_tlb_update_valid ? mmu_tlb_update_paddr : iommu_tlb_update_paddr)
    );

    // MMU
    mmu mmu_inst (
        .clk(clk), .reset(reset),
        .vaddr(i_addr | d_addr | prefetch_mmu_addr),
        .translate_request(icache_mmu_request | dcache_mmu_request | prefetch_mmu_request),
        .paddr(mmu_paddr), .translation_done(mmu_done), .fault(mmu_fault),
        .tlb_update_valid(mmu_tlb_update_valid), .tlb_update_vaddr(mmu_tlb_update_vaddr), .tlb_update_paddr(mmu_tlb_update_paddr)
    );

    // IOMMU
    iommu iommu_inst (
        .clk(clk), .reset(reset),
        .tlb_paddr(tlb_paddr), .tlb_hit(tlb_hit),
        .daddr(device_request ? device_addr : dma_iommu_daddr),
        .translate_request(device_request | dma_iommu_translate_request),
        .write_en(device_request ? device_write_en : dma_iommu_write_en),
        .write_data(device_request ? device_write_data : dma_iommu_write_data),
        .paddr(iommu_paddr), .data_out(iommu_data_out), .translation_done(iommu_done), .fault(iommu_fault),
        .tlb_update_valid(iommu_tlb_update_valid), .tlb_update_vaddr(iommu_tlb_update_vaddr), .tlb_update_paddr(iommu_tlb_update_paddr),
        .l2_addr(iommu_l2_addr), .l2_request(iommu_l2_request), .l2_write_data(iommu_l2_write_data), .l2_write_en(iommu_l2_write_en),
        .l2_data(iommu_l2_data), .l2_done(l2_done),
        .ram_read_address(iommu_ram_addr), .ram_read_en(iommu_ram_read_en), .ram_data_out(ram_data)
    );

    // DMA Engine
    dma_engine dma_inst (
        .clk(clk), .reset(reset),
        .src_addr(dma_src_addr), .dst_addr(dma_dst_addr), .size(dma_size), .start(dma_start),
        .done(dma_done), .error(dma_error),
        .iommu_daddr(dma_iommu_daddr), .iommu_translate_request(dma_iommu_translate_request),
        .iommu_write_en(dma_iommu_write_en), .iommu_write_data(dma_iommu_write_data),
        .iommu_paddr(iommu_paddr), .iommu_data_out(iommu_data_out),
        .iommu_translation_done(iommu_done), .iommu_fault(iommu_fault)
    );

    // L1 ICache
    l1_icache icache_inst (
        .clk(clk), .reset(reset),
        .tlb_paddr(tlb_paddr), .tlb_hit(tlb_hit),
        .vaddr(i_addr), .read_en(i_read_en),
        .data_out(i_data), .hit(i_hit), .miss(i_miss),
        .mmu_request(icache_mmu_request), .mmu_paddr(mmu_paddr), .mmu_done(mmu_done),
        .l2_addr(icache_l2_addr), .l2_request(icache_l2_request), .l2_data(icache_l2_data), .l2_done(l2_done),
        .prefetch_addr(icache_prefetch_addr), .prefetch_data(icache_prefetch_data), .prefetch_valid(icache_prefetch_valid)
    );

    // L1 DCache
    l1_dcache dcache_inst (
        .clk(clk), .reset(reset),
        .tlb_paddr(tlb_paddr), .tlb_hit(tlb_hit),
        .vaddr(d_addr), .read_en(d_read_en), .write_en(d_write_en), .write_data(d_write_data),
        .data_out(d_data), .hit(d_hit), .miss(d_miss),
        .mmu_request(dcache_mmu_request), .mmu_paddr(mmu_paddr), .mmu_done(mmu_done),
        .l2_addr(dcache_l2_addr), .l2_request(dcache_l2_request), .l2_write_data(dcache_l2_write_data), .l2_write_en(dcache_l2_write_en),
        .l2_data(dcache_l2_data), .l2_done(l2_done),
        .prefetch_addr(dcache_prefetch_addr), .prefetch_data(dcache_prefetch_data), .prefetch_valid(dcache_prefetch_valid)
    );

    // Prefetcher
    prefetcher prefetch_inst (
        .clk(clk), .reset(reset),
        .icache_miss(i_miss), .icache_addr(i_addr),
        .dcache_miss(d_miss), .dcache_addr(d_addr),
        .mmu_addr(prefetch_mmu_addr), .mmu_request(prefetch_mmu_request), .mmu_paddr(mmu_paddr), .mmu_done(mmu_done),
        .l2_addr(prefetch_l2_addr), .l2_request(prefetch_l2_request), .l2_data(prefetch_l2_data), .l2_done(l2_done),
        .icache_prefetch_addr(icache_prefetch_addr), .icache_prefetch_data(icache_prefetch_data), .icache_prefetch_valid(icache_prefetch_valid),
        .dcache_prefetch_addr(dcache_prefetch_addr), .dcache_prefetch_data(dcache_prefetch_data), .dcache_prefetch_valid(dcache_prefetch_valid)
    );

    // L2 Cache
    l2_cache l2_inst (
        .clk(clk), .reset(reset),
        .paddr(icache_l2_addr | dcache_l2_addr | iommu_l2_addr | prefetch_l2_addr),
        .request(icache_l2_request | dcache_l2_request | iommu_l2_request | prefetch_l2_request),
        .write_en(dcache_l2_write_en | iommu_l2_write_en),
        .write_data({256'b0, dcache_l2_write_en ? dcache_l2_write_data : iommu_l2_write_data}),
        .data_out({icache_l2_data, dcache_l2_data, iommu_l2_data, prefetch_l2_data}), .done(l2_done),
        .ram_addr(l2_ram_addr), .ram_read_en(l2_ram_read_en), .ram_write_en(l2_ram_write_en),
        .ram_data_in(l2_ram_data_in), .ram_data(ram_data)
    );

    // RAM (30-bit address, 16KB array)
    ram ram_inst (
        .clk(clk),
        .addr(l2_ram_addr | iommu_ram_addr),
        .read_en(l2_ram_read_en | iommu_ram_read_en),
        .write_en(l2_ram_write_en),
        .data_in(l2_ram_data_in),
        .data_out(ram_data)
    );

    // Device outputs
    assign device_data = iommu_data_out;
    assign device_done = device_request & iommu_done;
    assign device_fault = device_request & iommu_fault;
endmodule