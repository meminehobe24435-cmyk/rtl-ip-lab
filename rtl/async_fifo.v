// 异步 FIFO：格雷码指针 + 两级同步器跨时钟域，空满与"几乎满/几乎空"可编程阈值
// 设计要点：多 bit 二进制指针跨时钟域会因各位到达时间不同产生错误采样，格雷码每次只变 1 bit，
//          配合两级同步器即可安全传递；空满判断用"格雷码高两位取反"的经典做法，避免额外比较器延迟。
`timescale 1ns/1ps
module async_fifo #(
    parameter DATA_WIDTH  = 8,
    parameter ADDR_WIDTH  = 4,          // 深度 = 2**ADDR_WIDTH
    parameter ALMOST_FULL  = 2,
    parameter ALMOST_EMPTY = 2
) (
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [DATA_WIDTH-1:0] wdata,
    output reg                   wfull,
    output wire                  walmost_full,
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    output reg  [DATA_WIDTH-1:0] rdata,
    output reg                   rempty,
    output wire                  ralmost_empty
);
    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH:0] wbin, wgray, rbin, rgray;
    reg [ADDR_WIDTH:0] rq1, rq2;        // 读指针同步到写时钟域
    reg [ADDR_WIDTH:0] wq1, wq2;        // 写指针同步到读时钟域

    wire [ADDR_WIDTH:0] wbin_next  = wbin + ((winc && !wfull) ? 1'b1 : 1'b0);
    wire [ADDR_WIDTH:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [ADDR_WIDTH:0] rbin_next  = rbin + ((rinc && !rempty) ? 1'b1 : 1'b0);
    wire [ADDR_WIDTH:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    // 二进制 → 格雷码
    function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
        begin bin2gray = (b >> 1) ^ b; end
    endfunction

    // 格雷码 → 二进制（用于统计占用量，做"几乎满/几乎空"判断）
    function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
        integer i;
        begin
            gray2bin[ADDR_WIDTH] = g[ADDR_WIDTH];
            for (i = ADDR_WIDTH-1; i >= 0; i = i - 1)
                gray2bin[i] = gray2bin[i+1] ^ g[i];
        end
    endfunction

    // ---- 写侧 ----
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin wbin <= 0; wgray <= 0; end
        else         begin wbin <= wbin_next; wgray <= wgray_next; end
    end

    always @(posedge wclk) if (winc && !wfull) mem[wbin[ADDR_WIDTH-1:0]] <= wdata;

    // 读指针同步进写时钟域
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin rq1 <= 0; rq2 <= 0; end
        else         begin rq1 <= rgray; rq2 <= rq1; end
    end

    // 满：下一个写格雷码 == {读格雷码高两位取反, 其余不变}
    wire [ADDR_WIDTH:0] wfull_cmp = {~rq2[ADDR_WIDTH:ADDR_WIDTH-1], rq2[ADDR_WIDTH-2:0]};
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= (wgray_next == wfull_cmp);
    end

    // ---- 读侧 ----
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin rbin <= 0; rgray <= 0; end
        else         begin rbin <= rbin_next; rgray <= rgray_next; end
    end

    always @(posedge rclk) if (rinc && !rempty) rdata <= mem[rbin[ADDR_WIDTH-1:0]];

    // 写指针同步进读时钟域
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin wq1 <= 0; wq2 <= 0; end
        else         begin wq1 <= wgray; wq2 <= wq1; end
    end

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= (rgray_next == wq2);
    end

    // ---- 占用统计与阈值标志 ----
    wire [ADDR_WIDTH:0] wlevel = wbin - gray2bin(rq2);
    wire [ADDR_WIDTH:0] rlevel = gray2bin(wq2) - rbin;
    assign walmost_full  = (wlevel >= (DEPTH - ALMOST_FULL));
    assign ralmost_empty = (rlevel <= ALMOST_EMPTY);
endmodule
