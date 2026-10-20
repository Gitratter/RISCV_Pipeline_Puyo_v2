`timescale 1ns/1ps
`default_nettype none
// CPU executes all game rules. Hardware provides conditioned buttons, time,
// atomic display publication and VGA scanout in one 25 MHz clock domain.
module PuyoSoftwareSystem #(
    parameter integer CLK_HZ=25000000,
    parameter integer DEBOUNCE_MS=10,
    parameter IMEM_INIT_FILE="puyo_game.mem",
    parameter DMEM_INIT_FILE="puyo_game_data.mem"
)(
    input wire clk, reset,
    input wire raw_left,raw_right,raw_down,raw_rot_l,raw_rot_r,raw_restart,
    output wire [3:0] vga_red,vga_green,vga_blue,
    output wire hsync,vsync,
    output wire [15:0] led
);
    wire tick_ms;
    wire [31:0] milliseconds;
    MillisecondTick #(.CLK_HZ(CLK_HZ)) timer(
        .clk(clk),.reset(reset),.tick_ms(tick_ms),.milliseconds(milliseconds));
    wire [5:0] stable_keys;
    // Keep this instance name and the first synchronizer FF name for the XDC.
    PuyoButtons #(.DEBOUNCE_MS(DEBOUNCE_MS)) controls(
        .clk(clk),.reset(reset),.tick_ms(tick_ms),
        .raw_left(raw_left),.raw_right(raw_right),.raw_down(raw_down),
        .raw_rot_l(raw_rot_l),.raw_rot_r(raw_rot_r),.raw_restart(raw_restart),
        .stable_keys(stable_keys));

    wire mmio_valid,mmio_write,mmio_ready;
    wire [31:0] mmio_addr,mmio_wdata,mmio_rdata;
    wire [31:0] cycles,retired,mem_stalls,load_stalls,flushes;
    wire fault;
    wire [7:0] legacy_output;
    // The BRAM control cone is driven only by synchronous-reset CPU state.
    reg cpu_reset=1'b1;
    always @(posedge clk) cpu_reset<=reset;
    TD8_RISCV_V31_Core #(.IMEM_INIT_FILE(IMEM_INIT_FILE),.DMEM_INIT_FILE(DMEM_INIT_FILE)) cpu(
        .clk(clk),.reset(cpu_reset),.cpu_enable(1'b1),.input_port(8'd0),
        .debug_reg_addr(5'd0),.output_port(legacy_output),
        .debug_pc(),.debug_instruction(),.debug_reg_data(),.debug_mem_word0(),
        .debug_trap_cause(),.debug_trap_value(),.fault(fault),
        .retire_valid(),.retire_pc(),.retire_instruction(),
        .mmio_valid(mmio_valid),.mmio_write(mmio_write),.mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),.mmio_rdata(mmio_rdata),.mmio_ready(mmio_ready),
        .counter_cycle(cycles),.counter_instret(retired),.counter_mem_stall(mem_stalls),
        .counter_load_stall(load_stalls),.counter_flush(flushes));

    wire [251:0] board;
    wire [83:0] clear_mask;
    wire [3:0] active_x,active_y;
    wire [1:0] orientation;
    wire [2:0] color_a,color_b,next_a,next_b;
    wire [31:0] score;
    wire [7:0] chain,last_chain,phase;
    wire active_valid,busy,game_over,boot,frame_tick;
    PuyoSoftwareMMIO peripherals(
        .clk(clk),.reset(reset),.valid(mmio_valid),.write(mmio_write),
        .address(mmio_addr),.write_data(mmio_wdata),.ready(mmio_ready),.read_data(mmio_rdata),
        .stable_keys(stable_keys),.milliseconds(milliseconds),.frame_tick(frame_tick),
        .counter_cycle(cycles),.counter_instret(retired),.counter_mem_stall(mem_stalls),
        .counter_load_stall(load_stalls),.counter_flush(flushes),
        .board_flat(board),.clear_mask(clear_mask),.active_x(active_x),.active_y(active_y),
        .orientation(orientation),.color_a(color_a),.color_b(color_b),
        .next_a(next_a),.next_b(next_b),.score(score),.chain(chain),.last_chain(last_chain),
        .phase(phase),.active_valid(active_valid),.busy(busy),.game_over(game_over),.boot(boot));

    PuyoVideo video(.clk(clk),.reset(reset),.board_flat(board),.active_valid(active_valid),
        .active_x(active_x),.active_y(active_y),.orientation(orientation),
        .color_a(color_a),.color_b(color_b),.next_a(next_a),.next_b(next_b),
        .score(score),.chain(chain),.last_chain(last_chain),.game_over(game_over),
        .busy(busy),.clear_mask(clear_mask),.vga_red(vga_red),.vga_green(vga_green),
        .vga_blue(vga_blue),.hsync(hsync),.vsync(vsync),.frame_tick(frame_tick));
    assign led={fault,game_over,busy,boot,retired[19:16],legacy_output};
endmodule

// The board ports and hierarchy match the reviewed v4 Basys 3 constraints.
module TD8_RISCV_PUYO_TOP(
    input wire clk, input wire [15:0] sw,
    input wire btnL,btnR,btnD,btnU,btnC,
    output wire [3:0] vgaRed,vgaGreen,vgaBlue,
    output wire Hsync,Vsync,
    output wire [15:0] led,
    output wire [6:0] seg, output wire [3:0] an, output wire dp
);
    wire clk25,locked,reset;
    Clock25 clock_generator(.clk100(clk),.reset(sw[15]),.clk25(clk25),.locked(locked));
    ResetSync reset_synchronizer(.clk(clk25),.async_reset(sw[15] || !locked),.reset(reset));
    PuyoSoftwareSystem system(.clk(clk25),.reset(reset),.raw_left(btnL),.raw_right(btnR),
        .raw_down(btnD),.raw_rot_l(btnC),.raw_rot_r(btnU),.raw_restart(sw[14]),
        .vga_red(vgaRed),.vga_green(vgaGreen),.vga_blue(vgaBlue),
        .hsync(Hsync),.vsync(Vsync),.led(led));
    assign seg=7'b1111111;
    assign an=4'b1111;
    assign dp=1'b1;
endmodule
`default_nettype wire
