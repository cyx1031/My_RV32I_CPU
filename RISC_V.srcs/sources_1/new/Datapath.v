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
    reg [WIDTH-1:0] regs [0:31];
    assign rdata_1 = (raddr_1 == 5'd0) ? 32'd0 : regs[raddr_1];//read1
    assign rdata_2 = (raddr_2 == 5'd0) ? 32'd0 : regs[raddr_2];//read2
    
    always @(posedge CLK) begin//write
        if (we==1 && waddr != 5'd0) begin
            regs[waddr] <= wdata;
        end
    end
endmodule

module mux_21 #(//2进1多路选择器
    parameter WIDTH =32
) (
    input wire [WIDTH-1:0]in_0,
    input wire [WIDTH-1:0]in_1,
    input wire sel,
    output wire [WIDTH-1:0]out
);
    assign  out = (sel == 1'd0) ? in_0 : in_1;
endmodule

module PC_Register #(//程序计数器1
    parameter WIDTH = 32
) (
    input  wire CLK,
    input  wire reset,           
    input  wire [WIDTH-1:0] next_PC,   
    output reg  [WIDTH-1:0] current_PC 
);
    always @(posedge CLK) begin
        if (reset) 
            current_PC <= 32'd0;     
        else 
            current_PC <= next_PC;   
    end
endmodule

module PC_Adder #(//程序计数器2
    parameter WIDTH = 32
) (
    input  wire [WIDTH-1:0] PC_in,
    output wire [WIDTH-1:0] PC_out
);
    assign PC_out = PC_in + 32'd4; 
endmodule

module InstMem #(//程序存储器
    parameter WIDTH = 32
) (
    input wire [WIDTH-1:0] PC_addr,
    output wire [WIDTH-1:0] inst_out
);
    reg [WIDTH-1:0]rom [0:1023];
    wire [9:0] word_addr; 
    assign word_addr = PC_addr[31:2];
    assign inst_out = rom[word_addr];
    initial begin

    end

endmodule

module immGen #(//立即数生成器
    parameter WIDTH = 32
) (
    input wire [WIDTH-1:0] inst,
    input wire [3:0] immSel,//I,S,B,J,U
    output reg [WIDTH-1:0] Imm_out
);
    always @(*) begin
        case (immSel)
            4'd0 : Imm_out = { {20{inst[31]}} , inst[31:20] };//I
            4'd1 : Imm_out = { {20{inst[31]}} , inst[31:25] , inst[11:7]};//S
            4'd2 : Imm_out = { {20{inst[31]}} , inst[7] , inst[30:25] , inst[11:8] ,1'b0};//B
            4'd3 : Imm_out = { {12{inst[31]}} , inst[19:12] , inst[20] , inst[30:21] , 1'b0};//J
            4'd4 : Imm_out = { {inst[31:12]}  , 12'b0};//U
            default: Imm_out = 32'b0;
        endcase
    end
endmodule

module DataMem #(   //数据存储器
    parameter WIDTH =32
) (
    input wire [WIDTH-1:0] Draddr,
    input wire [WIDTH-1:0] Dwdata,
    output wire [WIDTH-1:0]Drdata,
    input wire Dwe,
    input wire CLK
);
    reg [WIDTH-1:0] regs [0:1023];
    wire [9:0] Dword_addr = Draddr[11:2];
    assign Drdata = regs[Dword_addr];//read
    
      always @(posedge CLK) begin//write
        if (Dwe) begin
            regs[Dword_addr] <= Dwdata;
        end
            
    end
endmodule

module Control_Unit  #(//控制单元
    parameter WIDTH =32
) (
    input wire [WIDTH-1:0] inst,
    output reg Branch,//分支？
    output reg MemRead,//lw?读取内存？
    output reg MemWrite,//sw?写入内存？
    output reg RegWrite,//写入reg?
    output reg [1:0]MemtoReg,//写入reg来自ALU(0)/读内存
    output reg ALUSrc,//ALU数据来自reg(0)/Imm?
    output reg [3:0] ALUControl,//ALUselect
    output reg [3:0]ImmSel,//立即数格式？
    output reg Jump
);
    wire [6:0]opcode = inst[6:0];//做什么操作
    wire [2:0]funct3  = inst[14:12];//做什么指令？
    wire funct7_bit5 = inst[30];//区分add/sub,srl/sra
    reg  [1:0] ALUOp ;//给ALU的解码器：
    //2'b00：内存指令；2'b01：分支；2'b10：R-Type；2'b11： I-Type；
    always @(*) begin
        Branch     = 0;
        MemRead    = 0;
        MemWrite   = 0;
        RegWrite   = 0;
        MemtoReg   = 2'b00;
        ALUSrc     = 0;
        ImmSel     = 4'd0;
        ALUOp      = 2'b00;
        Jump       = 0; 
        case (opcode)
        7'b0110011: //R-Type 纯寄存器运算
        begin
            RegWrite = 1; ALUOp = 2'b10;
        end
        7'b0010011://I-Type 立即数运算
        begin
            RegWrite = 1; ALUSrc = 1; ALUOp = 2'b11; ImmSel = 4'd0;
        end
        7'b0000011://Load 读内存
        begin
            MemRead = 1; RegWrite = 1; MemtoReg = 2'b01; ALUSrc = 1; ALUOp = 2'b00; ImmSel = 4'd0;
        end
        7'b0100011://Store 写内存
        begin
            MemWrite = 1; ALUSrc = 1; ALUOp = 2'b00; ImmSel = 4'd1;
        end
        7'b1100011://B-Type 条件跳转
        begin
            Branch = 1; ALUOp = 2'b01; ImmSel = 4'd2;
        end
        7'b1101111://J-Type 无条件跳转
        begin
            Jump = 1; RegWrite = 1; MemtoReg = 2'b10; ALUOp = 2'b01; ImmSel = 4'd3;
        end
        7'b0110111://U-Type 高位立即数
        begin
            RegWrite = 1; MemtoReg = 2'b11; ImmSel = 4'd4;
        end
        endcase
    end
    always @(*) begin
        ALUControl = 4'd0;  
        case (ALUOp)//给ALU的信号
            2'b00 : ALUControl = 4'd0 ;//内存指令加法算地址
            2'b01 : ALUControl = 4'd1;//Branch指令减法算条件
            2'b10 ://R-Type
            begin
                case (funct3)
                    3'b000 : begin
                    if (!funct7_bit5) ALUControl = 4'd0;
                    else ALUControl = 4'd1;
                    end
                    3'b001 : ALUControl = 4'd5; 
                    3'b010 : ALUControl = 4'd8;
                    3'b011 : ALUControl = 4'd9;
                    3'b100 : ALUControl = 4'd4;
                    3'b101 : begin
                    if (!funct7_bit5) ALUControl = 4'd6;
                    else ALUControl = 4'd7;
                    end
                    3'b110 : ALUControl = 4'd3;
                    3'b111 : ALUControl = 4'd2;
                endcase
            end
            2'b11 ://I-Type
            begin
                case (funct3)
                    3'b000 : ALUControl = 4'd0; 
                    3'b001 : ALUControl = 4'd5; 
                    3'b010 : ALUControl = 4'd8;
                    3'b011 : ALUControl = 4'd9;
                    3'b100 : ALUControl = 4'd4;
                    3'b101 : begin
                    if (!funct7_bit5) ALUControl = 4'd6;
                    else ALUControl = 4'd7;
                    end
                    3'b110 : ALUControl = 4'd3;
                    3'b111 : ALUControl = 4'd2;
                endcase
            end
        endcase
    end

endmodule