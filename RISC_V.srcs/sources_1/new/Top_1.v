`timescale 1ns / 1ps

module Top_1(
    input wire CLK,
    input wire reset
    );
    // ===========================================================================
    // 内部信号声明(Internal Signals)
    // ===========================================================================
    //===PC相关
    wire [31:0] current_PC;//当前地址
    wire [31:0] PC_plus_4;
    wire [31:0] next_pc;//下一条指令的地址
    //===控制单元相关
    wire [31:0] inst;
    wire branch;//分支？
    wire memRead;//lw?读取内存？
    wire memWrite;//sw?写入内存？
    wire regWrite;//写入reg?
    wire [1:0] memtoreg;//写入reg来自ALU(0)/读内存
    wire alusrc;//ALU数据来自reg(0)/Imm?
    wire [3:0] alucontrol;//ALUselect
    wire [3:0] immsel;//立即数格式？
    wire jump;//JAL跳转标识符
    wire [31:0]immout;//立即数输出
    //===寄存器相关
    wire [31:0]mem_rdata;
    wire [31:0]wb_data;
    wire [31:0]rdata_1;
    wire [31:0]rdata_2;
    wire [31:0]alu_result;
    //===ALU相关
    wire [31:0]alu_in2;
    wire alu_zero;
    //===分支跳转（专为JAL,BEQ服务）
    wire branch_taken = (branch & alu_zero) | jump;//执行beq/JAL?
    wire [31:0] branch_target = current_PC + immout;//跳转目标地址是哪里？
    // ===========================================================================
    // 模块实例化 (Module Instantiations)
    // ===========================================================================
    PC_Adder pc_add(//PC+4
        .PC_in  ( current_PC),     
        .PC_out ( PC_plus_4 )      
    );
    PC_Register pc_reg(//输出下一条指令
        .CLK        ( CLK        ),
        .reset      ( reset      ),
        .next_PC    ( next_pc    ),    
        .current_PC ( current_PC )
    );
    
    InstMem u_instmem(//发出32位指令
        .PC_addr  ( current_PC ),
        .inst_out ( inst       )
    );
    Control_Unit u_ctrl(
        .inst      ( inst      ),
        .Branch    ( branch    ),
        .MemRead   ( memRead   ),
        .MemWrite  ( memWrite  ),
        .RegWrite  ( regWrite  ),
        .MemtoReg  ( memtoreg  ),
        .ALUSrc    ( alusrc    ),
        .ALUControl( alucontrol),
        .ImmSel    ( immsel    ),
        .Jump      ( jump      )
    );
    immGen u_immgen(//立即数生成
        .inst    ( inst   ),
        .immSel  ( immsel ),
        .Imm_out ( immout )
    );

    Mux_41 u_mux_41_2(//写入寄存器值的来自ALU/IMM？
        .in_0 ( alu_result),//ALU
        .in_1 ( mem_rdata ),//MEM
        .in_2 ( PC_plus_4 ),//PC+4(JAL)
        .in_3 ( immout    ),//LUI
        .sel  ( memtoreg  ),
        .out  ( wb_data   )
    ); 
    RegFile u_regfile(//寄存器堆
        .CLK     ( CLK          ),
        .raddr_1 ( inst[19:15]  ),//RS1值
        .raddr_2 ( inst[24:20]  ),//RS2值
        .we      ( regWrite     ),// 写使能
        .waddr   ( inst[11:7]   ),//写入地址
        .wdata   ( wb_data      ),
        .rdata_1 ( rdata_1      ),
        .rdata_2 ( rdata_2      )
    );
    Mux_21 u_mux21_1(
        .in_0 ( rdata_2 ),
        .in_1 ( immout  ),
        .sel  ( alusrc  ),
        .out  ( alu_in2 )
    );
    ALU u_alu(
        .nub_1  ( rdata_1   ),
        .nub_2  ( alu_in2   ),
        .select ( alucontrol),
        .Result ( alu_result),
        .Zero   ( alu_zero  )
    );
    DataMem u_datamem(
        .Draddr ( alu_result),
        .Dwdata ( rdata_2   ),
        .Drdata ( mem_rdata ),
        .Dwe    ( memWrite  ),
        .CLK    ( CLK       )
    );
    Mux_21 u_mux21_2(//是执行下一条还是B/J-Type?
        .in_0 ( PC_plus_4    ),
        .in_1 ( branch_target),
        .sel  ( branch_taken ),
        .out  ( next_pc      )  
    );
endmodule
