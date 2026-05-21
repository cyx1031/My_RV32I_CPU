`timescale 1ns / 1ps

module Top_Pipeline(
    input wire CLK,
    input wire reset
);

    // ===========================================================================
    // 0. 全局控制信号 & 内部连线声明
    // ===========================================================================
    wire        Stall;          // 来自 HazardDetectionUnit
    wire        PC_Write;       // = ~Stall
    wire        IF_ID_Write;    // = ~Stall
    wire        Flush;          // 分支/跳转时冲刷流水线

    // --- IF 阶段信号 ---
    wire [31:0] current_PC;
    wire [31:0] PC_plus_4;
    wire [31:0] next_pc;
    wire [31:0] inst_from_mem;

    // --- ID 阶段信号 (IF/ID 寄存器输出) ---
    wire [31:0] ifid_inst;
    wire [31:0] ifid_PC;

    // --- ID 阶段：控制单元输出 ---
    wire        id_branch;
    wire        id_memRead;
    wire        id_memWrite;
    wire        id_regWrite;
    wire [1:0]  id_memtoReg;
    wire        id_aluSrc;
    wire [3:0]  id_aluControl;
    wire [3:0]  id_immSel;
    wire        id_jump;
    wire [31:0] id_immout;

    // --- ID 阶段：寄存器堆输出 ---
    wire [31:0] id_rdata1;
    wire [31:0] id_rdata2;

    // --- EX 阶段信号 (ID/EX 寄存器输出) ---
    wire [31:0] ex_PC;
    wire [31:0] ex_rdata1;
    wire [31:0] ex_rdata2;
    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [31:0] ex_imm;
    wire [4:0]  ex_rd;
    wire        ex_branch;
    wire        ex_memRead;
    wire        ex_memWrite;
    wire        ex_regWrite;
    wire [1:0]  ex_memtoReg;
    wire        ex_aluSrc;
    wire [3:0]  ex_aluControl;
    wire        ex_jump;

    // --- EX 阶段：Forwarding & ALU ---
    wire [1:0]  ForwardA;
    wire [1:0]  ForwardB;
    wire [31:0] alu_srcA;       // 经过 Forward Mux 后的 ALU 输入A
    wire [31:0] forward_B_out;  // 经过 Forward Mux 后的值（还没经过 ALUSrc Mux）
    wire [31:0] alu_srcB;       // 经过 ALUSrc Mux 后的 ALU 输入B
    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    // --- MEM 阶段信号 (EX/MEM 寄存器输出) ---
    wire [31:0] mem_PC;
    wire [31:0] mem_alu_result;
    wire        mem_alu_zero;
    wire [31:0] mem_rdata2;
    wire [31:0] mem_imm;
    wire [4:0]  mem_rd;
    wire        mem_branch;
    wire        mem_memRead;
    wire        mem_memWrite;
    wire        mem_regWrite;
    wire [1:0]  mem_memtoReg;
    wire        mem_jump;

    // --- MEM 阶段：DataMem & 分支判断 ---
    wire [31:0] mem_read_data;
    wire [31:0] branch_target;
    wire        branch_taken;

    // --- WB 阶段信号 (MEM/WB 寄存器输出) ---
    wire [31:0] wb_PC;
    wire [31:0] wb_alu_result;
    wire [31:0] wb_mem_rdata;
    wire [31:0] wb_imm;
    wire [4:0]  wb_rd;
    wire        wb_regWrite;
    wire [1:0]  wb_memtoReg;

    // --- WB 阶段：写回数据 ---
    wire [31:0] wb_data;

    // ===========================================================================
    // 全局控制逻辑
    // ===========================================================================
    assign PC_Write    = ~Stall;
    assign IF_ID_Write = ~Stall;
    assign Flush       = branch_taken; // 分支/跳转成立时，冲刷 IF/ID 和 ID/EX

    // ===========================================================================
    // 1. IF 阶段 (取指)
    // ===========================================================================
    PC_Register pc_reg(
        .CLK        ( CLK        ),
        .reset      ( reset      ),
        .PC_Write   ( PC_Write   ),
        .next_PC    ( next_pc    ),
        .current_PC ( current_PC )
    );

    PC_Adder pc_add(
        .PC_in  ( current_PC ),
        .PC_out ( PC_plus_4  )
    );

    InstMem u_instmem(
        .PC_addr  ( current_PC    ),
        .inst_out ( inst_from_mem )
    );

    // PC 来源选择：正常 PC+4 / 分支跳转目标
    Mux_21 u_pc_mux(
        .in_0 ( PC_plus_4     ),
        .in_1 ( branch_target ),
        .sel  ( branch_taken  ),
        .out  ( next_pc       )
    );

    // ===========================================================================
    // IF/ID 流水线寄存器
    // ===========================================================================
    IF_ID u_if_id(
        .CLK            ( CLK            ),
        .IF_ID_reset    ( Flush          ),  // 分支成立时冲刷
        .IF_ID_Write    ( IF_ID_Write    ),  // Stall 时冻结
        .IF_ID_inst_in  ( inst_from_mem  ),
        .IF_ID_PC_in    ( current_PC     ),
        .IF_ID_inst_out ( ifid_inst      ),
        .IF_ID_PC_out   ( ifid_PC        )
    );

    // ===========================================================================
    // 2. ID 阶段 (译码)
    // ===========================================================================
    Control_Unit u_ctrl(
        .inst       ( ifid_inst     ),
        .Branch     ( id_branch     ),
        .MemRead    ( id_memRead    ),
        .MemWrite   ( id_memWrite   ),
        .RegWrite   ( id_regWrite   ),
        .MemtoReg   ( id_memtoReg   ),
        .ALUSrc     ( id_aluSrc     ),
        .ALUControl ( id_aluControl ),
        .ImmSel     ( id_immSel     ),
        .Jump       ( id_jump       )
    );

    immGen u_immgen(
        .inst    ( ifid_inst ),
        .immSel  ( id_immSel ),
        .Imm_out ( id_immout )
    );

    RegFile u_regfile(
        .CLK     ( CLK              ),
        .raddr_1 ( ifid_inst[19:15] ),
        .raddr_2 ( ifid_inst[24:20] ),
        .we      ( wb_regWrite      ),  // 写使能来自 WB 阶段
        .waddr   ( wb_rd            ),  // 写地址来自 WB 阶段
        .wdata   ( wb_data          ),  // 写数据来自 WB 阶段
        .rdata_1 ( id_rdata1        ),
        .rdata_2 ( id_rdata2        )
    );

    HazardDetectionUnit u_hazard(
        .IF_ID_rs1   ( ifid_inst[19:15] ),
        .IF_ID_rs2   ( ifid_inst[24:20] ),
        .ID_EX_rd    ( ex_rd            ),
        .ID_EX_MemRead ( ex_memRead     ),
        .Stall       ( Stall            )
    );

    // ===========================================================================
    // ID/EX 流水线寄存器
    // 注意：Stall 或 Flush 时，控制信号全部清零（插入气泡）
    // ===========================================================================
    ID_EX u_id_ex(
        .CLK              ( CLK                              ),
        .ID_EX_reset      ( Stall | Flush                    ),  // Stall或Flush时插入气泡
        .ID_EX_Write      ( 1'b1                             ),  // ID/EX 始终可写
        .ID_EX_PC         ( ifid_PC                          ),
        .ID_EX_rdata1     ( id_rdata1                        ),
        .ID_EX_rdata2     ( id_rdata2                        ),
        .ID_EX_rs1        ( ifid_inst[19:15]                 ),
        .ID_EX_rs2        ( ifid_inst[24:20]                 ),
        .ID_EX_imm        ( id_immout                        ),
        .ID_EX_rd         ( ifid_inst[11:7]                  ),
        .ID_EX_Branch     ( Stall ? 1'b0 : id_branch        ),
        .ID_EX_MemRead    ( Stall ? 1'b0 : id_memRead       ),
        .ID_EX_MemWrite   ( Stall ? 1'b0 : id_memWrite      ),
        .ID_EX_RegWrite   ( Stall ? 1'b0 : id_regWrite      ),
        .ID_EX_MemtoReg   ( Stall ? 2'b0 : id_memtoReg      ),
        .ID_EX_ALUSrc     ( Stall ? 1'b0 : id_aluSrc        ),
        .ID_EX_ALUControl ( Stall ? 4'b0 : id_aluControl    ),
        .ID_EX_Jump       ( Stall ? 1'b0 : id_jump          ),

        .o_ID_EX_PC         ( ex_PC         ),
        .o_ID_EX_rdata1     ( ex_rdata1     ),
        .o_ID_EX_rdata2     ( ex_rdata2     ),
        .o_ID_EX_rs1        ( ex_rs1        ),
        .o_ID_EX_rs2        ( ex_rs2        ),
        .o_ID_EX_imm        ( ex_imm        ),
        .o_ID_EX_rd         ( ex_rd         ),
        .o_ID_EX_Branch     ( ex_branch     ),
        .o_ID_EX_MemRead    ( ex_memRead    ),
        .o_ID_EX_MemWrite   ( ex_memWrite   ),
        .o_ID_EX_RegWrite   ( ex_regWrite   ),
        .o_ID_EX_MemtoReg   ( ex_memtoReg   ),
        .o_ID_EX_ALUSrc     ( ex_aluSrc     ),
        .o_ID_EX_ALUControl ( ex_aluControl ),
        .o_ID_EX_Jump       ( ex_jump       )
    );

    // ===========================================================================
    // 3. EX 阶段 (执行)
    // ===========================================================================
    ForwardingUnit u_forward(
        .ID_EX_rs1       ( ex_rs1        ),
        .ID_EX_rs2       ( ex_rs2        ),
        .EX_MEM_rd       ( mem_rd        ),
        .EX_MEM_RegWrite ( mem_regWrite  ),
        .MEM_WB_rd       ( wb_rd         ),
        .MEM_WB_RegWrite ( wb_regWrite   ),
        .ForwardA        ( ForwardA      ),
        .ForwardB        ( ForwardB      )
    );

    // ALU 输入A：3选1 (00:寄存器原值, 10:EX/MEM转发, 01:WB转发)
    Mux_41 u_fwd_muxA(
        .sel  ( ForwardA        ),
        .in_0 ( ex_rdata1       ),  // 00: 正常，来自寄存器
        .in_1 ( wb_data         ),  // 01: 来自 WB 阶段
        .in_2 ( mem_alu_result  ),  // 10: 来自 MEM 阶段 (EX/MEM)
        .in_3 ( 32'b0           ),  // 11: 未使用
        .out  ( alu_srcA        )
    );

    // ALU 输入B 的 Forward 选择：3选1
    Mux_41 u_fwd_muxB(
        .sel  ( ForwardB        ),
        .in_0 ( ex_rdata2       ),  // 00: 正常
        .in_1 ( wb_data         ),  // 01: 来自 WB 阶段
        .in_2 ( mem_alu_result  ),  // 10: 来自 MEM 阶段
        .in_3 ( 32'b0           ),  // 11: 未使用
        .out  ( forward_B_out   )
    );

    // ALUSrc Mux：选择 ALU 第二个输入是寄存器值还是立即数
    Mux_21 u_alusrc_mux(
        .in_0 ( forward_B_out ),  // 来自寄存器（经过转发）
        .in_1 ( ex_imm        ),  // 来自立即数
        .sel  ( ex_aluSrc     ),
        .out  ( alu_srcB      )
    );

    ALU u_alu(
        .nub_1  ( alu_srcA     ),
        .nub_2  ( alu_srcB     ),
        .select ( ex_aluControl),
        .Result ( ex_alu_result),
        .Zero   ( ex_alu_zero  )
    );

    // ===========================================================================
    // EX/MEM 流水线寄存器
    // ===========================================================================
    EX_MEM u_ex_mem(
        .CLK              ( CLK            ),
        .EX_MEM_reset     ( reset          ),
        .EX_MEM_PC        ( ex_PC          ),
        .EX_MEM_alu_result( ex_alu_result  ),
        .EX_MEM_alu_zero  ( ex_alu_zero    ),
        .EX_MEM_rdata2    ( forward_B_out  ),  // sw 写内存的数据（经过转发）
        .EX_MEM_imm       ( ex_imm         ),
        .EX_MEM_rd        ( ex_rd          ),
        .EX_MEM_Branch    ( ex_branch      ),
        .EX_MEM_MemRead   ( ex_memRead     ),
        .EX_MEM_MemWrite  ( ex_memWrite    ),
        .EX_MEM_RegWrite  ( ex_regWrite    ),
        .EX_MEM_MemtoReg  ( ex_memtoReg    ),
        .EX_MEM_Jump      ( ex_jump        ),

        .o_EX_MEM_PC        ( mem_PC         ),
        .o_EX_MEM_alu_result( mem_alu_result ),
        .o_EX_MEM_alu_zero  ( mem_alu_zero   ),
        .o_EX_MEM_rdata2    ( mem_rdata2     ),
        .o_EX_MEM_imm       ( mem_imm        ),
        .o_EX_MEM_rd        ( mem_rd         ),
        .o_EX_MEM_Branch    ( mem_branch     ),
        .o_EX_MEM_MemRead   ( mem_memRead    ),
        .o_EX_MEM_MemWrite  ( mem_memWrite   ),
        .o_EX_MEM_RegWrite  ( mem_regWrite   ),
        .o_EX_MEM_MemtoReg  ( mem_memtoReg   ),
        .o_EX_MEM_Jump      ( mem_jump       )
    );

    // ===========================================================================
    // 4. MEM 阶段 (访存)
    // ===========================================================================
    // 分支判断：在 MEM 阶段决定是否跳转
    assign branch_taken  = (mem_branch & mem_alu_zero) | mem_jump;
    assign branch_target = mem_PC + mem_imm;

    DataMem u_datamem(
        .CLK    ( CLK            ),
        .Dwe    ( mem_memWrite   ),
        .Draddr ( mem_alu_result ),
        .Dwdata ( mem_rdata2     ),
        .Drdata ( mem_read_data  )
    );

    // ===========================================================================
    // MEM/WB 流水线寄存器
    // ===========================================================================
    MEM_WB u_mem_wb(
        .CLK              ( CLK            ),
        .MEM_WB_reset     ( reset          ),
        .MEM_WB_PC        ( mem_PC         ),
        .MEM_WB_alu_result( mem_alu_result ),
        .MEM_WB_mem_rdata ( mem_read_data  ),
        .MEM_WB_imm       ( mem_imm        ),
        .MEM_WB_rd        ( mem_rd         ),
        .MEM_WB_RegWrite  ( mem_regWrite   ),
        .MEM_WB_MemtoReg  ( mem_memtoReg   ),

        .o_MEM_WB_PC        ( wb_PC         ),
        .o_MEM_WB_alu_result( wb_alu_result ),
        .o_MEM_WB_mem_rdata ( wb_mem_rdata  ),
        .o_MEM_WB_imm       ( wb_imm        ),
        .o_MEM_WB_rd        ( wb_rd         ),
        .o_MEM_WB_RegWrite  ( wb_regWrite   ),
        .o_MEM_WB_MemtoReg  ( wb_memtoReg   )
    );

    // ===========================================================================
    // 5. WB 阶段 (写回)
    // ===========================================================================
    // wb_data 的来源：ALU结果 / 内存数据 / PC+4(JAL) / 立即数(LUI)
    wire [31:0] wb_PC_plus_4 = wb_PC + 32'd4;

    Mux_41 u_wb_mux(
        .sel  ( wb_memtoReg   ),
        .in_0 ( wb_alu_result ),  // 00: ALU 结果
        .in_1 ( wb_mem_rdata  ),  // 01: 内存读出的数据 (lw)
        .in_2 ( wb_PC_plus_4  ),  // 10: PC+4 (JAL 的返回地址)
        .in_3 ( wb_imm        ),  // 11: 立即数 (LUI)
        .out  ( wb_data       )
    );

endmodule