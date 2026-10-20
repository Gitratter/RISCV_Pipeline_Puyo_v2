`timescale 1ns/1ps
`default_nettype none

// Xilinx 7-series synchronous block RAM inference templates. Configuration
// initialization is supported; runtime reset deliberately never clears arrays.
module PipelineInstructionMemoryV31 #(
    parameter integer WORDS=4096,
    parameter integer INIT_DEMO=0,
    parameter INIT_FILE=""
)(
    input wire clk,
    input wire enable,
    input wire [31:0] address,
    output reg [31:0] instruction
);
    (* rom_style = "block" *) reg [31:0] memory [0:WORDS-1];
    localparam integer ADDRESS_BITS=$clog2(WORDS);
    wire [ADDRESS_BITS-1:0] word_index=address[ADDRESS_BITS+1:2];
    integer i;
    initial begin
        instruction=32'h00000013;
        for(i=0;i<WORDS;i=i+1) memory[i]=32'h00000013;
        if(INIT_DEMO!=0 && WORDS>=9) begin
            memory[0]=32'h10000093;
            memory[1]=32'h10400113;
            memory[2]=32'h0000a183;
            memory[3]=32'h05a1c193;
            memory[4]=32'h00119193;
            memory[5]=32'h003000a3;
            memory[6]=32'h00104203;
            memory[7]=32'h00412023;
            memory[8]=32'hfe9ff06f;
        end
        if(INIT_FILE!="") $readmemh(INIT_FILE,memory);
    end
    always @(posedge clk) if(enable) begin
        if(address[31:2]<WORDS && address[1:0]==2'b00)
            instruction<=memory[word_index];
        else instruction<=32'h00000013;
    end
endmodule

module PipelineDataMemoryV31 #(
    parameter integer ENABLE_DEBUG=0,
    parameter INIT_FILE=""
)(
    input wire clk,
    input wire enable,
    input wire [3:0] write_strobe,
    input wire [31:0] address,
    input wire [31:0] write_data,
    output reg [31:0] read_data,
    output wire [31:0] debug_word0
);
    (* ram_style = "block" *) reg [31:0] memory [0:1023];
    wire [9:0] word_index=address[11:2];
    integer i;
    initial begin
        read_data=0;
        for(i=0;i<1024;i=i+1) memory[i]=0;
        // Harvard CPU: C read-only data resides in DATA BRAM, not instruction ROM.
        // Firmware startup clears BSS on every CPU reset. Mutable .data is forbidden.
        if(INIT_FILE!="") $readmemh(INIT_FILE,memory);
    end
    always @(posedge clk) if(enable) begin
        read_data<=memory[word_index];
        if(write_strobe[0]) memory[word_index][7:0]<=write_data[7:0];
        if(write_strobe[1]) memory[word_index][15:8]<=write_data[15:8];
        if(write_strobe[2]) memory[word_index][23:16]<=write_data[23:16];
        if(write_strobe[3]) memory[word_index][31:24]<=write_data[31:24];
    end
    // Enable only in simulation: an extra asynchronous debug port prevents
    // single-port BRAM inference. Production top leaves this parameter zero.
    generate if(ENABLE_DEBUG!=0) begin:g_debug
        assign debug_word0=memory[0];
    end else begin:g_no_debug
        assign debug_word0=0;
    end endgenerate
endmodule
`default_nettype wire
