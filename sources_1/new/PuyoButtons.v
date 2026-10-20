`timescale 1ns/1ps
`default_nettype none
// Physical input conditioning only. The RV32I program owns edges, DAS and ARR.
// stable_keys: left, right, down, rotate-left, rotate-right, restart (bits 0..5).
module PuyoButtons #(
    parameter integer DEBOUNCE_MS=10
)(
    input wire clk, reset, tick_ms,
    input wire raw_left, raw_right, raw_down, raw_rot_l, raw_rot_r, raw_restart,
    output reg [5:0] stable_keys
);
    localparam integer DB=(DEBOUNCE_MS<1) ? 1 : DEBOUNCE_MS;
    localparam integer COUNT_WIDTH=(DB<2) ? 1 : $clog2(DB);
    wire [5:0] raw_keys={raw_restart,raw_rot_r,raw_rot_l,raw_down,raw_right,raw_left};
    (* ASYNC_REG="TRUE" *) reg [5:0] sync_meta, sync_clean;
    reg [COUNT_WIDTH-1:0] debounce_count[0:5];
    integer b;
    always @(posedge clk) begin
        if(reset) begin
            sync_meta<=0;
            sync_clean<=0;
            stable_keys<=0;
            for(b=0;b<6;b=b+1) debounce_count[b]<=0;
        end else begin
            sync_meta<=raw_keys;
            sync_clean<=sync_meta;
            if(tick_ms) begin
                for(b=0;b<6;b=b+1) begin
                    if(sync_clean[b]==stable_keys[b]) debounce_count[b]<=0;
                    else if(debounce_count[b]==DB-1) begin
                        stable_keys[b]<=sync_clean[b];
                        debounce_count[b]<=0;
                    end else debounce_count[b]<=debounce_count[b]+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
