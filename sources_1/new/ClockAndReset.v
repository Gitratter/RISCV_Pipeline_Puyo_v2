`timescale 1ns/1ps
`default_nettype none
// Basys 3 oscillator 100 MHz -> MMCM VCO 1000 MHz -> system/pixel 25 MHz.
// SIMULATION is selected explicitly by the simulation runner, never synthesis.
module Clock25(input wire clk100, input wire reset, output wire clk25, output wire locked);
`ifdef SIMULATION
    reg [1:0] divider = 0;
    always @(posedge clk100 or posedge reset)
        if (reset) divider <= 0; else divider <= divider + 1'b1;
    assign clk25 = divider[1];
    assign locked = !reset;
`else
    wire feedback_raw, feedback, clock_raw;
    MMCME2_BASE #(.BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(40.0),
        .STARTUP_WAIT("FALSE")) mmcm (
        .CLKIN1(clk100), .RST(reset), .PWRDWN(1'b0),
        .CLKFBIN(feedback), .CLKFBOUT(feedback_raw), .CLKFBOUTB(),
        .CLKOUT0(clock_raw), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(),
        .CLKOUT5(), .CLKOUT6(), .LOCKED(locked));
    BUFG feedback_buffer(.I(feedback_raw), .O(feedback));
    BUFG system_buffer(.I(clock_raw), .O(clk25));
`endif
endmodule

module ResetSync(input wire clk, input wire async_reset, output wire reset);
    (* ASYNC_REG = "TRUE" *) reg [2:0] sync_ff = 3'b111;
    always @(posedge clk or posedge async_reset)
        if (async_reset) sync_ff <= 3'b111;
        else sync_ff <= {sync_ff[1:0], 1'b0};
    assign reset = sync_ff[2];
endmodule

module MillisecondTick #(parameter integer CLK_HZ = 25000000)(
    input wire clk, input wire reset, output reg tick_ms, output reg [31:0] milliseconds);
    localparam integer DIVISOR = CLK_HZ / 1000;
    localparam integer CW = (DIVISOR < 2) ? 1 : $clog2(DIVISOR);
    reg [CW-1:0] count;
    always @(posedge clk) begin
        if (reset) begin count <= 0; tick_ms <= 0; milliseconds <= 0; end
        else begin
            tick_ms <= 0;
            if (count == DIVISOR-1) begin
                count <= 0; tick_ms <= 1; milliseconds <= milliseconds + 1'b1;
            end else count <= count + 1'b1;
        end
    end
endmodule
`default_nettype wire
