// SPI 主控（模式 0：CPOL=0 / CPHA=0）：可配置分频、片选、8 位收发、MISO 在上升沿采样
// 设计要点：sclk 由计数器分频产生，收发都只在"移位时刻"动作一次；
//          片选在传输前后各留一个半周期，避免首末位被从机误采。
`timescale 1ns/1ps
module spi_master #(
    parameter CLK_DIV = 4,          // sclk 半周期 = CLK_DIV 个系统时钟
    parameter WIDTH   = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [WIDTH-1:0]  tx_data,
    input  wire              miso,
    output reg               sclk,
    output reg               mosi,
    output reg               cs_n,
    output reg  [WIDTH-1:0]  rx_data,
    output reg               busy,
    output reg               done,
    output reg  [7:0]        bit_cnt
);
    localparam S_IDLE = 2'd0, S_CS = 2'd1, S_SHIFT = 2'd2, S_END = 2'd3;

    reg [1:0]        state;
    reg [15:0]       div_cnt;
    reg [WIDTH-1:0]  sh_tx, sh_rx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; sclk <= 0; mosi <= 0; cs_n <= 1;
            rx_data <= 0; busy <= 0; done <= 0; div_cnt <= 0;
            sh_tx <= 0; sh_rx <= 0; bit_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        sh_tx  <= tx_data;
                        sh_rx  <= 0;
                        cs_n   <= 1'b0;
                        sclk   <= 1'b0;
                        busy   <= 1'b1;
                        div_cnt <= 0;
                        bit_cnt <= 0;
                        state  <= S_CS;                 // 片选后先等半个周期
                    end
                end
                S_CS: begin
                    if (div_cnt == CLK_DIV-1) begin
                        div_cnt <= 0;
                        mosi    <= sh_tx[WIDTH-1];      // 模式 0：第一个上升沿前就准备好数据
                        state   <= S_SHIFT;
                    end else div_cnt <= div_cnt + 1'b1;
                end
                S_SHIFT: begin
                    if (div_cnt == CLK_DIV-1) begin
                        div_cnt <= 0;
                        if (sclk == 1'b0) begin
                            sclk  <= 1'b1;                                 // 上升沿
                            sh_rx <= {sh_rx[WIDTH-2:0], miso};             // 模式 0：主机在上升沿采样 MISO
                        end else begin
                            sclk    <= 1'b0;                               // 下降沿
                            sh_tx   <= {sh_tx[WIDTH-2:0], 1'b0};
                            mosi    <= sh_tx[WIDTH-2];                     // 切换下一位 MOSI
                            bit_cnt <= bit_cnt + 1'b1;
                            if (bit_cnt == WIDTH-1) state <= S_END;
                        end
                    end else div_cnt <= div_cnt + 1'b1;
                end
                S_END: begin
                    if (div_cnt == CLK_DIV-1) begin
                        div_cnt <= 0;
                        cs_n    <= 1'b1;
                        rx_data <= sh_rx;
                        busy    <= 1'b0;
                        done    <= 1'b1;
                        state   <= S_IDLE;
                    end else div_cnt <= div_cnt + 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
