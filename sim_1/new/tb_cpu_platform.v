`timescale 1ns/1ps
`default_nettype none
module tb_cpu_platform;
    reg clk=0,reset=1,cpu_enable=0;
    always #5 clk=~clk;
    reg [4:0] debug_reg_addr=0;
    wire [31:0] reg_data,pc,insn,mem0,trap_value;
    wire [4:0] cause;
    wire [7:0] out_port;
    wire fault,retire,valid,write;
    wire [31:0] retire_pc,retire_insn,addr,wdata;
    wire [31:0] cycles,instret,mem_stall,load_stall,flush;
    reg [3:0] wait_count=0;
    wire ready=(wait_count==4);
    integer writes=0,reads=0,stores=0,retired=0,p=0,t=0;
    integer held_writes,held_stores,held_retired;
    reg [31:0] held_pc;
    reg saw_pause_pending=0,saw_pause_response=0;
    `include "rv32i_encode.vh"
    TD8_RISCV_V31_Core #(.IMEM_WORDS(4096),.ENABLE_RF_DEBUG(1),.ENABLE_MEM_DEBUG(1)) dut(
        .clk(clk),.reset(reset),.cpu_enable(cpu_enable),.input_port(8'ha5),
        .debug_reg_addr(debug_reg_addr),.output_port(out_port),.debug_pc(pc),
        .debug_instruction(insn),.debug_reg_data(reg_data),.debug_mem_word0(mem0),
        .debug_trap_cause(cause),.debug_trap_value(trap_value),.fault(fault),
        .retire_valid(retire),.retire_pc(retire_pc),.retire_instruction(retire_insn),
        .mmio_valid(valid),.mmio_write(write),.mmio_addr(addr),.mmio_wdata(wdata),
        .mmio_rdata(32'h1234abcd),.mmio_ready(ready),
        .counter_cycle(cycles),.counter_instret(instret),.counter_mem_stall(mem_stall),
        .counter_load_stall(load_stall),.counter_flush(flush));
    always @(posedge clk) if(!reset) begin
        if(valid) begin
            if(ready) begin
                wait_count<=0;
                if(write) begin
                    writes<=writes+1;
                    if(addr!==32'h2000 || wdata!==32'h5a)
                        $fatal(1,"wrong or wrong-path MMIO store addr=%x data=%x",addr,wdata);
                end else begin
                    reads<=reads+1;
                    if(addr!==32'h2004) $fatal(1,"wrong MMIO read");
                end
            end else wait_count<=wait_count+1;
        end
        if(dut.ram_write_strobe!=0) stores<=stores+1;
        if(retire) begin
            retired<=retired+1;
            if(retire_pc==96 || retire_pc==100 || retire_pc>=116)
                $fatal(1,"wrong-path or faulting instruction retired pc=%x",retire_pc);
        end
    end
    task emit(input [31:0] word);
        begin dut.instruction_memory.memory[p]=word; p=p+1; end
    endtask
    task check_reg(input [4:0] regnum,input [31:0] expected);
        begin debug_reg_addr=regnum; #1;
            if(reg_data!==expected) $fatal(1,"x%0d expected=%x actual=%x",regnum,expected,reg_data);
        end
    endtask
    task pause_and_check;
        begin
            cpu_enable=0;
            held_pc=dut.pc;
            held_writes=writes;held_stores=stores;held_retired=retired;
            repeat(6) begin @(posedge clk); #1;
                if(dut.pc!==held_pc || writes!=held_writes || stores!=held_stores || retired!=held_retired || valid)
                    $fatal(1,"pause changed architectural state or repeated transaction");
            end
            @(negedge clk);cpu_enable=1;
        end
    endtask
    initial begin
        #1;
        emit(rv32_u(20'h1,1,RV32_OPCODE_LUI));                              // 0
        emit(rv32_u(20'h88776,2,RV32_OPCODE_LUI));                          // 4
        emit(rv32_i('h655,2,0,2,RV32_OPCODE_OP_IMM));                       // 8
        emit(rv32_s(0,2,1,2,RV32_OPCODE_STORE));                           // 12
        emit(rv32_s(1,2,1,0,RV32_OPCODE_STORE));                           // 16
        emit(rv32_i('h80,0,0,3,RV32_OPCODE_OP_IMM));                        // 20
        emit(rv32_s(2,3,1,0,RV32_OPCODE_STORE));                           // 24
        emit(rv32_i('h123,0,0,3,RV32_OPCODE_OP_IMM));                       // 28
        emit(rv32_s(2,3,1,1,RV32_OPCODE_STORE));                           // 32
        emit(rv32_i(0,1,2,4,RV32_OPCODE_LOAD));                            // 36
        emit(rv32_i(1,4,0,5,RV32_OPCODE_OP_IMM));                          // 40
        emit(rv32_i(-1,0,0,3,RV32_OPCODE_OP_IMM));                         // 44
        emit(rv32_s(3,3,1,0,RV32_OPCODE_STORE));                           // 48
        emit(rv32_i(3,1,0,6,RV32_OPCODE_LOAD));                            // 52
        emit(rv32_i(3,1,4,7,RV32_OPCODE_LOAD));                            // 56
        emit(rv32_i(2,1,1,8,RV32_OPCODE_LOAD));                            // 60
        emit(rv32_i(2,1,5,9,RV32_OPCODE_LOAD));                            // 64
        emit(rv32_i(0,0,2,10,RV32_OPCODE_LOAD));                           // 68
        emit(rv32_u(20'h2,11,RV32_OPCODE_LUI));                            // 72
        emit(rv32_s(-4,5,11,2,RV32_OPCODE_STORE));                         // 76
        emit(rv32_i(-4,11,2,12,RV32_OPCODE_LOAD));                         // 80
        emit(rv32_i('h5a,0,0,13,RV32_OPCODE_OP_IMM));                       // 84
        emit(rv32_s(0,13,11,2,RV32_OPCODE_STORE));                         // 88
        emit(rv32_b(12,0,0,0,RV32_OPCODE_BRANCH));                         // 92
        emit(rv32_s(8,13,11,2,RV32_OPCODE_STORE));                         // 96 wrong
        emit(32'hffffffff);                                              //100 wrong
        emit(rv32_i(4,11,2,14,RV32_OPCODE_LOAD));                          //104
        emit(rv32_i(1,14,0,15,RV32_OPCODE_OP_IMM));                         //108
        emit(32'h00100073);                                               //112 EBREAK
        emit(rv32_s(12,13,11,2,RV32_OPCODE_STORE));                        //116 younger
        repeat(2) @(posedge clk); @(negedge clk);reset=0;cpu_enable=1;
        // Pause with an unacknowledged request, then with an acknowledged
        // response buffered. Neither may create duplicated peripheral writes.
        wait(valid && !write && wait_count==2); @(negedge clk);
        pause_and_check; saw_pause_pending=1;
        wait(dut.mem_done && dut.mem_is_external_mmio && !dut.ex_mem_mem_write);
        @(negedge clk);pause_and_check;saw_pause_response=1;
        while(!fault && t<500) begin @(posedge clk);#1;t=t+1;end
        if(!fault || cause!==3 || pc!==112) $fatal(1,"precise EBREAK failed pc=%x cause=%d",pc,cause);
        check_reg(4,32'h01235555);check_reg(5,32'h01235556);
        check_reg(6,32'hffffffff);check_reg(7,32'hff);
        check_reg(8,32'hffffff23);check_reg(9,32'hff23);
        check_reg(10,32'hff235555);check_reg(12,32'h01235556);
        check_reg(14,32'h1234abcd);check_reg(15,32'h1234abce);
        if(writes!=1 || reads!=1 || stores!=6) $fatal(1,"duplicate/missing effects writes=%d reads=%d RAM stores=%d",writes,reads,stores);
        if(instret!==26 || retired!=26 || mem_stall==0 || load_stall!=2 || flush!=2)
            $fatal(1,"counter mismatch instret=%d retired=%d mem=%d load=%d flush=%d",instret,retired,mem_stall,load_stall,flush);
        if(!saw_pause_pending || !saw_pause_response) $fatal(1,"pause tests not reached");
        if(dut.data_memory.memory[1023]!==32'h01235556) $fatal(1,"last RAM word wrong");
        repeat(10) @(posedge clk);
        if(writes!=1 || reads!=1 || stores!=6 || retired!=26) $fatal(1,"sticky fault allowed side effect");
        $display("PASS: tb_cpu_platform (sync RAM lanes/alias/end/load-use/MMIO waits/pause/flush/trap/counters)");
        $finish;
    end
    initial begin #30000;$fatal(1,"timeout CPU platform");end
endmodule
`default_nettype wire
