// 自检 testbench：异步 FIFO —— 写满/读空标志、数据顺序、跨时钟域并发读写、阈值标志
`timescale 1ns/1ps
module tb_async_fifo;
    localparam DW = 8, AW = 4, DEPTH = 16;
    reg wclk = 0, rclk = 0, wrst_n = 0, rrst_n = 0, winc = 0, rinc = 0;
    reg  [DW-1:0] wdata = 0;
    wire [DW-1:0] rdata;
    wire wfull, rempty, walmost_full, ralmost_empty;

    integer errors = 0, checks = 0;
    task check(input cond, input [255:0] name);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("  FAIL  %0s", name); end
            else                                  $display("  PASS  %0s", name);
        end
    endtask

    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .ALMOST_FULL(2), .ALMOST_EMPTY(2)) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata),
        .wfull(wfull), .walmost_full(walmost_full),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata),
        .rempty(rempty), .ralmost_empty(ralmost_empty)
    );

    always #5 wclk = ~wclk;      // 100 MHz
    always #7 rclk = ~rclk;      // 读时钟不同频（约 71 MHz）

    integer i, order_ok, rd_i, wr_i;
    reg rd_valid;
    reg [DW-1:0] rd_data;
    reg w_ok;
    integer wr_cnt = 0;
    reg [DW-1:0] written [0:127];
    reg [DW-1:0] expect;

    // 统一在 negedge 驱动激励、下一个 negedge 采样，彻底避开与 posedge 的竞争
    task fifo_write(input [DW-1:0] d);
        begin
            @(negedge wclk);
            if (!wfull) begin winc = 1'b1; wdata = d; end
            else              winc = 1'b0;
            @(negedge wclk);
            winc = 1'b0;
        end
    endtask

    task fifo_write2(input [DW-1:0] d, output reg ok);
        begin
            ok = 1'b0;
            @(negedge wclk);
            if (!wfull) begin winc = 1'b1; wdata = d; ok = 1'b1; end
            else              winc = 1'b0;
            @(negedge wclk);
            winc = 1'b0;
        end
    endtask

    task fifo_read(output [DW-1:0] d, output reg valid);
        begin
            valid = 1'b0;
            @(negedge rclk);
            if (!rempty) begin rinc = 1'b1; valid = 1'b1; end
            else              rinc = 1'b0;
            @(negedge rclk);
            rinc = 1'b0;
            d = rdata;
        end
    endtask
    reg [DW-1:0] captured [0:63];
    integer cap_cnt = 0;

    initial begin
        $display("=== TB: async_fifo ===");
        repeat (3) @(posedge wclk);
        wrst_n = 1; rrst_n = 1;
        repeat (2) @(posedge wclk);

        check(rempty === 1'b1, "复位后读空标志为 1");
        check(wfull  === 1'b0, "复位后写满标志为 0");

        // ---- 写入 10 个数据：此时占用 10 < 深度-2，几乎满不应置位 ----
        for (i = 0; i < 10; i = i + 1) fifo_write(8'h10 + i);
        check(rempty === 1'b0, "写入 10 个后不再是读空");
        check(walmost_full === 1'b0, "占用 10 < 深度-2 时几乎满不置位");
        check(ralmost_empty === 1'b0, "占用 10 时几乎空不置位");

        // ---- 读出并核对顺序 ----
        for (i = 0; i < 10; i = i + 1) begin
            fifo_read(expect, rd_valid);
            check(rd_valid && expect === (8'h10 + i), "读出的数据顺序正确");
        end
        @(negedge rclk); @(negedge rclk);
        check(rempty === 1'b1, "读完后回到读空");
        check(ralmost_empty === 1'b1, "占用 <= 2 时几乎空置位（空时成立）");

        // ---- 一直写到满：写满标志必须拦住后续写入 ----
        for (i = 0; i < DEPTH + 4; i = i + 1) fifo_write((8'h40 + i) & 8'hFF);
        @(negedge wclk); @(negedge wclk);
        check(wfull === 1'b1, "写满后写满标志为 1");
        check(walmost_full === 1'b1, "满时几乎满同时置位");

        // ---- 读空：数据必须是前 DEPTH 个（多写的被满标志丢掉） ----
        for (i = 0; i < DEPTH; i = i + 1) begin
            fifo_read(expect, rd_valid);
            check(rd_valid && expect === ((8'h40 + i) & 8'hFF), "满→空过程中数据顺序正确");
        end
        @(negedge rclk); @(negedge rclk);
        check(rempty === 1'b1, "全部读出后读空标志为 1");

        // ---- 并发读写：两个时钟域同时跑，核对不丢不重 ----
        cap_cnt = 0;
        fork
            begin : writer
                for (wr_i = 0; wr_i < 80; wr_i = wr_i + 1) begin
                    fifo_write2(wr_i[DW-1:0], w_ok);
                    if (w_ok) begin                       // 记录"真正写进去"的序列
                        written[wr_cnt] = wr_i[DW-1:0];
                        wr_cnt = wr_cnt + 1;
                    end
                end
            end
            begin : reader
                for (rd_i = 0; rd_i < 80; rd_i = rd_i + 1) begin
                    fifo_read(rd_data, rd_valid);
                    if (rd_valid) begin                       // 只记录真正读到的数据
                        captured[cap_cnt] = rd_data;
                        cap_cnt = cap_cnt + 1;
                    end
                end
            end
        join
        check(cap_cnt > 20, "并发读写期间收到了足够的数据（无丢包）");
        // 正确判据：读者读到的序列，必须与写者"实际写进去"的序列逐一相符
        // （写满时写者会跳过写入，所以不能要求数值连续 +1）
        order_ok = (cap_cnt > 0) && (cap_cnt <= wr_cnt);
        for (i = 0; i < cap_cnt; i = i + 1)
            if (captured[i] !== written[i]) order_ok = 0;
        check(order_ok == 1, "并发读写：读出的序列与写入的序列完全一致（不丢不重）");

        $display("TB async_fifo: %0d 项检查, %0d 项失败", checks, errors);
        if (errors == 0) $display("RESULT: ALL PASS"); else $display("RESULT: FAILED");
        $finish;
    end
endmodule
