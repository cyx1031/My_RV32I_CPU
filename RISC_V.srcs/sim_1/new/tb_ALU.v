`timescale 1ns / 1ps

module tb_ALU();

    // 定义信号，直接给初始值 0
    reg  [31:0] tb_nub_1 = 32'd0;
    reg  [31:0] tb_nub_2 = 32'd0;
    reg  [3:0]  tb_select = 4'd0;
    
    wire [31:0] tb_Result;
    wire        tb_Zero;

    // 把你的 ALU 实例化进来
    ALU #(
        .WIDTH(32)
    ) u_ALU (
        .nub_1 (tb_nub_1),   
        .nub_2 (tb_nub_2),
        .select(tb_select),
        .Result(tb_Result),  
        .Zero  (tb_Zero)
    );

    // 注意：这里没有任何 initial 块！全靠你在 Vivado 里手动拨开关！

endmodule