// AXI4-Stream 读通道 DMA：按描述符（源地址 + 长度）发起传输，逐拍从 AXI-Stream 取数并写入内存
// 设计要点：valid/ready 双向握手必须"只在双方同一拍都为高时才认为传输发生"；
//          上游可以随时收回 ready（背压），所以状态机必须能停在 REQ 态不动数据。
`timescale 1ns/1ps
module axis_dma #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter LEN_WIDTH  = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire [ADDR_WIDTH-1:0] dst_addr,
    input  wire [LEN_WIDTH-1:0]  length,      // 字节数，0 视为非法
    // AXI4-Stream 从机侧（本模块是 stream 的接收方 / 内存的写方）
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tlast,
    // 简化内存写接口
    output reg                   mem_we,
    output reg  [ADDR_WIDTH-1:0] mem_addr,
    output reg  [DATA_WIDTH-1:0] mem_wdata,
    // 状态
    output reg                   busy,
    output reg                   done,
    output reg                   err,
    output reg  [LEN_WIDTH-1:0]  transferred
);
    localparam S_IDLE = 2'd0, S_XFER = 2'd1, S_DONE = 2'd2, S_ERR = 2'd3;

    reg [1:0]            state;
    reg [LEN_WIDTH-1:0]  remain;
    reg [ADDR_WIDTH-1:0] addr_r;

    assign s_axis_tready = (state == S_XFER) && !done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            err         <= 1'b0;
            transferred <= 0;
            remain      <= 0;
            addr_r      <= 0;
            mem_we      <= 1'b0;
            mem_addr    <= 0;
            mem_wdata   <= 0;
        end else begin
            mem_we <= 1'b0;                      // 默认单拍脉冲
            case (state)
                S_IDLE: begin
                    done <= 1'b0; err <= 1'b0;
                    if (start) begin
                        if (length == 0) begin
                            state <= S_ERR; err <= 1'b1; busy <= 1'b0;
                        end else begin
                            remain      <= length;
                            addr_r      <= dst_addr;
                            transferred <= 0;
                            busy        <= 1'b1;
                            state       <= S_XFER;
                        end
                    end
                end
                S_XFER: begin
                    // 只有 valid && ready 同一拍为高，才产生一次数据传输
                    if (s_axis_tvalid && s_axis_tready) begin
                        mem_we    <= 1'b1;
                        mem_addr  <= addr_r;
                        mem_wdata <= s_axis_tdata;
                        addr_r      <= addr_r + 1'b1;
                        transferred <= transferred + 1'b1;
                        remain      <= remain - 1'b1;
                        if (remain == 1) state <= S_DONE;      // 最后一拍
                    end
                end
                S_DONE: begin
                    busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
                end
                S_ERR: begin
                    busy <= 1'b0; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
