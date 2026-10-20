`timescale 1ns/1ps
`default_nettype none
// CPU-owned display staging and publication; there are no game rules here.
// Each valid && ready rising edge accepts exactly one MMIO transaction.
// A commit publishes all staged fields together. VGA takes its own frame copy.
module PuyoSoftwareMMIO(
    input wire clk, reset,
    input wire valid, write,
    input wire [31:0] address, write_data,
    output wire ready,
    output reg [31:0] read_data,
    input wire [5:0] stable_keys,
    input wire [31:0] milliseconds,
    input wire frame_tick,
    input wire [31:0] counter_cycle, counter_instret, counter_mem_stall,
    input wire [31:0] counter_load_stall, counter_flush,
    output reg [251:0] board_flat,
    output reg [83:0] clear_mask,
    output reg [3:0] active_x, active_y,
    output reg [1:0] orientation,
    output reg [2:0] color_a, color_b, next_a, next_b,
    output reg [31:0] score,
    output reg [7:0] chain, last_chain, phase,
    output reg active_valid, busy, game_over, boot
);
    reg [31:0] stage_index;
    reg [251:0] stage_board;
    reg [83:0] stage_clear;
    reg [15:0] stage_active;
    reg [5:0] stage_next;
    reg [31:0] stage_score;
    reg [27:0] stage_status;
    reg [31:0] frame_counter, publish_counter;
    wire transfer=valid && ready;
    assign ready=!reset;

    always @* begin
        read_data=0;
        case(address)
            32'h00002000: read_data={26'd0,stable_keys};
            32'h00002004: read_data=milliseconds;
            32'h00002008: read_data=counter_cycle;
            32'h0000200c: read_data=32'h50535935; // Software-game platform ID.
            32'h00002010: read_data=frame_counter;
            32'h00002014: read_data=publish_counter;
            32'h00002040: read_data=counter_cycle;
            32'h00002044: read_data=counter_instret;
            32'h00002048: read_data=counter_mem_stall;
            32'h0000204c: read_data=counter_load_stall;
            32'h00002050: read_data=counter_flush;
            default: read_data=0; // Reserved/read-from-write-only: zero.
        endcase
    end

    always @(posedge clk) begin
        if(reset) begin
            stage_index<=0; stage_board<=0; stage_clear<=0;
            stage_active<=0; stage_next<=0; stage_score<=0; stage_status<=0;
            board_flat<=0; clear_mask<=0;
            active_x<=0; active_y<=0; orientation<=0;
            color_a<=0; color_b<=0; next_a<=0; next_b<=0;
            score<=0; chain<=0; last_chain<=0; phase<=0;
            active_valid<=0; busy<=0; game_over<=0; boot<=0;
            frame_counter<=0; publish_counter<=0;
        end else begin
            if(frame_tick) frame_counter<=frame_counter+1'b1;
            if(transfer && write) begin
                case(address)
                    32'h00002020: stage_index<=write_data;
                    // Compare the entire index, not a truncated low-bit alias.
                    32'h00002024: if(stage_index<84) begin
                        stage_board[stage_index[6:0]*3 +: 3]<=write_data[2:0];
                        stage_clear[stage_index[6:0]]<=write_data[8];
                    end
                    32'h00002028: stage_active<=write_data[15:0];
                    32'h0000202c: stage_next<=write_data[5:0];
                    32'h00002030: stage_score<=write_data;
                    32'h00002034: stage_status<=write_data[27:0];
                    32'h00002038: if(write_data[0]) begin
                        board_flat<=stage_board;
                        clear_mask<=stage_clear;
                        active_x<=stage_active[3:0];
                        active_y<=stage_active[7:4];
                        orientation<=stage_active[9:8];
                        color_a<=stage_active[12:10];
                        color_b<=stage_active[15:13];
                        next_a<=stage_next[2:0];
                        next_b<=stage_next[5:3];
                        score<=stage_score;
                        chain<=stage_status[7:0];
                        last_chain<=stage_status[15:8];
                        phase<=stage_status[23:16];
                        active_valid<=stage_status[24];
                        busy<=stage_status[25];
                        game_over<=stage_status[26];
                        boot<=stage_status[27];
                        publish_counter<=publish_counter+1'b1;
                    end
                    default: ; // Read-only and reserved writes have no effect.
                endcase
            end
        end
    end
endmodule
`default_nettype wire
