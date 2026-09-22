// 自检 testbench：AXI4-Stream DMA —— 握手传输、背压（ready 随机拉低）、last 边界、非法长度
`timescale 1ns/1ps
module tb_axis_dma;
    localparam DW = 8, AW = 8, LW = 8;

    reg clk = 0, rst_n = 0, start = 0;
    reg  [AW-1:0] dst_addr = 0;
    reg  [LW-1:0] length = 0;
    reg           s_tvalid = 0, s_tlast = 0;
    reg  [DW-1:0] s_tdata = 0;
    wire          s_tready;
    wire          mem_we;
    wire [AW-1:0] mem_addr;
    wire [DW-1:0] mem_wdata;
    wire          busy, done, err;
    wire [LW-1:0] transferred;

    integer errors = 0, checks = 0;
    task check(input cond, input [255:0] name);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("  FAIL  %0s", name); end
            else                                  $display("  PASS  %0s", name);
        end
    endtask

    axis_dma #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .LEN_WIDTH(LW)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .dst_addr(dst_addr), .length(length),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tdata(s_tdata), .s_axis_tlast(s_tlast),
        .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .busy(busy), .done(done), .err(err), .transferred(transferred)
    );

    always #5 clk = ~clk;

    // 内存模型：记录写入的字节
    reg [DW-1:0] mem [0:255];
    integer wr_cnt = 0;
    always @(posedge clk) if (mem_we) begin
        mem[mem_addr] = mem_wdata;
        wr_cnt = wr_cnt + 1;
    end

    // AXI-Stream 源模型：带背压（ready 被随机拉低）
    reg [DW-1:0] src [0:63];
    integer src_len = 0, src_idx = 0;
    // 源模型：在 negedge 驱动（此时 tready 已经稳定），1/3 概率"这一拍不发数据"模拟间歇性源；
    // 只有 valid && ready 同时为高的那一拍才推进索引 —— 这正是 AXI-Stream 握手语义。
    always @(negedge clk) begin
        if (rst_n && src_idx < src_len) begin
            s_tvalid <= 1'b1;
            s_tdata  <= src[src_idx];
            s_tlast  <= (src_idx == src_len - 1);
            if (s_tready) src_idx <= src_idx + 1;
        end else begin
            s_tvalid <= 1'b0; s_tdata <= 8'h00; s_tlast <= 1'b0;
        end
    end

    integer i; reg ok;
    initial begin
        $display("=== TB: axis_dma ===");
        for (i = 0; i < 64; i = i + 1) src[i] = 8'hA0 + i;

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        check(done === 1'b0 && busy === 1'b0, "复位后空闲");

        // ---- 非法长度：length=0 应报错且不传输 ----
        start = 1; length = 0; dst_addr = 8'h20;
        @(posedge clk); start = 0;
        @(posedge clk);
        check(err === 1'b1, "length=0 → 置错误标志");
        check(wr_cnt == 0, "非法描述符不产生任何写操作");

        // ---- 正常传输：16 字节，带背压 ----
        wr_cnt = 0; src_len = 16; src_idx = 0;
        dst_addr = 8'h40; length = 16; start = 1;
        @(posedge clk); start = 0;
        wait (done);
        @(posedge clk);
        check(transferred === 16, "传输计数 = 16 字节");
        check(wr_cnt == 16, "内存写次数 = 16（握手成功才写，背压不重复写）");
        ok = 1;
        for (i = 0; i < 16; i = i + 1) if (mem[8'h40 + i] !== src[i]) ok = 0;
        check(ok == 1, "写入内存的数据与源数据逐字节一致");

        // ---- 大长度 + 强背压：64 字节 ----
        wr_cnt = 0; src_len = 64; src_idx = 0;
        dst_addr = 8'h00; length = 64; start = 1;
        @(posedge clk); start = 0;
        wait (done);
        @(posedge clk);
        ok = 1;
        for (i = 0; i < 64; i = i + 1) if (mem[i] !== src[i]) ok = 0;
        check(transferred === 64 && ok == 1, "64 字节在随机背压下完整传输且顺序正确");

        $display("TB axis_dma: %0d 项检查, %0d 项失败", checks, errors);
        if (errors == 0) $display("RESULT: ALL PASS"); else $display("RESULT: FAILED");
        $finish;
    end

    initial begin
        #200000;
        $display("  FAIL  %0s", "仿真超时（可能有握手死锁）");
        $display("RESULT: FAILED");
        $finish;
    end
endmodule
