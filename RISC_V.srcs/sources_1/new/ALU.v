`timescale 1ns / 1ps

module ALU #(
    parameter WIDTH = 32       
)(
    input  wire [WIDTH-1:0] nub_1,   
    input  wire [WIDTH-1:0] nub_2,
    input  wire [3:0] select,
    output reg  [WIDTH-1:0] Result,
    output reg   Zero
);
    always @(*) 
    begin
        case (select)
            4'd0 : Result = nub_1 + nub_2;
            4'd1 : Result = nub_1 - nub_2;
            4'd2 : Result = nub_1 & nub_2;//按位与AND
            4'd3 : Result = nub_1 | nub_2;//按位或OP
            4'd4 : Result = nub_1 ^ nub_2;//按位异或XOR
            4'd5 : Result = nub_1 << nub_2[4:0];//逻辑左移SLL
            4'd6 : Result = nub_1 >> nub_2[4:0];//逻辑右移SRL
            4'd7 : Result = $signed(nub_1) >>> nub_2[4:0];//算术右移SRA
            4'd8 : Result = $signed(nub_1) < $signed(nub_2);//有符号比较SLT
            4'd9 : Result = nub_1 < nub_2;//无符号比较SLTU
            default:  Result = 32'b0;  
        endcase
        if (Result==0) 
            Zero = 1;
        else Zero = 0;
    end
endmodule

module RegFile #(   //寄存器堆
    parameter WIDTH =32
) (
    input wire [4:0] raddr_1,
    input wire [4:0] raddr_2,
    output wire [WIDTH-1:0]rdata_1,
    output wire [WIDTH-1:0]rdata_2,
    input wire [4:0] waddr,
    input wire [WIDTH-1:0] wdata,
    input wire we,
    input wire CLK
);
    reg [WIDTH-1:0] regs [31:0];
    assign rdata_1 = (raddr_1 == 5'd0) ? 32'd0 : regs[raddr_1];//read1
    assign rdata_2 = (raddr_2 == 5'd0) ? 32'd0 : regs[raddr_2];//read2
    
    always @(posedge CLK) begin//write
        if (we==1 && waddr != 5'd0) begin
            regs[waddr] <= wdata;
        end
    end
endmodule

module mux_21 #(
    parameter WIDTH =32
) (
    input wire [WIDTH-1:0]in_0,
    input wire [WIDTH-1:0]in_1,
    input wire sel,
    output wire [WIDTH-1:0]out
);
    assign  out = (sel == 1'd0) ? in_0 : in_1;
endmodule