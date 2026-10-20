`timescale 1ns / 1ps
// 25 MHz pixel clock, 640x480 visible, 800x525 total, 59.5238 Hz.
// RGB, HSYNC and VSYNC are registered together (one pixel latency).
module PuyoVideo(
    input wire clk, reset,
    input wire [251:0] board_flat,
    input wire active_valid,
    input wire [3:0] active_x, active_y,
    input wire [1:0] orientation,
    input wire [2:0] color_a, color_b, next_a, next_b,
    input wire [31:0] score,
    input wire [7:0] chain, last_chain,
    input wire game_over, busy,
    input wire [83:0] clear_mask,
    output reg [3:0] vga_red, vga_green, vga_blue,
    output reg hsync, vsync,
    output reg frame_tick
);
    reg [9:0] pixel_x, pixel_y;
    reg [251:0] board_view;
    reg active_view, over_view, busy_view;
    reg [3:0] ax_view, ay_view;
    reg [1:0] orientation_view;
    reg [2:0] a_view, b_view, na_view, nb_view;
    reg [7:0] chain_view, last_view;
    reg [83:0] clear_view;
    reg [31:0] binary_score;
    reg [39:0] bcd_work, score_bcd;
    reg [5:0] bcd_steps;
    reg [39:0] bcd_adjust;
    integer digit;

    // Double-dabble conversion takes exactly 32 clocks in vertical blank.
    // No 32-bit division hardware is required for the decimal score.
    always @* begin
        bcd_adjust = bcd_work;
        for (digit=0;digit<10;digit=digit+1)
            if (bcd_work[digit*4 +: 4] >= 5)
                bcd_adjust[digit*4 +: 4] = bcd_work[digit*4 +: 4] + 4'd3;
    end

    always @(posedge clk) begin
        if (reset) begin
            pixel_x <= 0;
            pixel_y <= 0;
            frame_tick <= 0;
            board_view <= 0;
            active_view <= 0;
            ax_view <= 0;
            ay_view <= 0;
            orientation_view <= 0;
            a_view <= 0;
            b_view <= 0;
            na_view <= 0;
            nb_view <= 0;
            chain_view <= 0;
            last_view <= 0;
            over_view <= 0;
            busy_view <= 0;
            clear_view <= 0;
            binary_score <= 0;
            bcd_work <= 0;
            score_bcd <= 0;
            bcd_steps <= 0;
        end else begin
            frame_tick <= 0;
            if (pixel_x == 799) begin
                pixel_x <= 0;
                pixel_y <= pixel_y == 524 ? 10'd0 : pixel_y + 10'd1;
            end else pixel_x <= pixel_x + 10'd1;
            if (pixel_x == 0 && pixel_y == 480) begin
                frame_tick <= 1;
                board_view <= board_flat;
                active_view <= active_valid;
                ax_view <= active_x;
                ay_view <= active_y;
                orientation_view <= orientation;
                a_view <= color_a;
                b_view <= color_b;
                na_view <= next_a;
                nb_view <= next_b;
                chain_view <= chain;
                last_view <= last_chain;
                over_view <= game_over;
                busy_view <= busy;
                clear_view <= clear_mask;
                binary_score <= score;
                bcd_work <= 0;
                bcd_steps <= 32;
            end else if (bcd_steps != 0) begin
                bcd_work <= {bcd_adjust[38:0],binary_score[31]};
                binary_score <= {binary_score[30:0],1'b0};
                bcd_steps <= bcd_steps - 1'b1;
                if (bcd_steps == 1) score_bcd <= {bcd_adjust[38:0],binary_score[31]};
            end
        end
    end

    function [11:0] palette;
        input [2:0] color_id;
        begin
            case (color_id)
                1: palette = 12'hF45; // red
                2: palette = 12'h4E6; // green
                3: palette = 12'h49F; // blue
                4: palette = 12'hFD4; // yellow
                default: palette = 12'h122;
            endcase
        end
    endfunction

    // The sprite contract is just (color_id, local_x, local_y, marked).
    // Replace this function with a sprite-ROM reader to change appearance.
    function [11:0] puyo_pixel;
        input [2:0] color_id;
        input [4:0] sx, sy;
        input marked;
        reg body;
        begin
            body = sx>=3 && sx<=28 && sy>=3 && sy<=28 &&
                   !(sx<7 && sy<7) && !(sx>24 && sy<7) &&
                   !(sx<7 && sy>24) && !(sx>24 && sy>24);
            puyo_pixel = 12'h122;
            if (color_id!=0 && body) begin
                puyo_pixel = marked ? 12'hFFF : palette(color_id);
                if (sy>=10 && sy<=17 &&
                    ((sx>=9 && sx<=12) || (sx>=19 && sx<=22)))
                    puyo_pixel = 12'hFFF;
                if (sy>=13 && sy<=17 && (sx==11 || sx==21))
                    puyo_pixel = 12'h112;
            end
        end
    endfunction

    function [34:0] glyph;
        input [7:0] ch;
        begin
            case (ch)
                "0": glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1": glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2": glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3": glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4": glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6": glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7": glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8": glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9": glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A": glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C": glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D": glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G": glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "H": glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "J": glyph={5'b00111,5'b00010,5'b00010,5'b00010,5'b10010,5'b10010,5'b01100};
                "L": glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W": glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "X": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Y": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                ":": glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "/": glyph={5'b00001,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b10000};
                default: glyph=0;
            endcase
        end
    endfunction

    function [11:0] bcd8;
        input [7:0] value;
        reg [19:0] work;
        integer k, d;
        begin
            work={12'b0,value};
            for(k=0;k<8;k=k+1) begin
                for(d=0;d<3;d=d+1)
                    if(work[8+d*4 +: 4]>=5)
                        work[8+d*4 +: 4]=work[8+d*4 +: 4]+4'd3;
                work=work<<1;
            end
            bcd8=work[19:8];
        end
    endfunction

    reg [11:0] rgb;
    reg [2:0] tile_color;
    reg [4:0] tile_sx, tile_sy;
    reg tile_mark;
    integer board_x, board_y, board_index, satellite_x, satellite_y;
    reg text_enable;
    reg [127:0] text_line;
    reg [1:0] number_kind;
    reg [11:0] short_bcd;
    integer tx, ty, text_length, text_col, font_x, font_y;
    reg [7:0] character;
    reg [34:0] character_bits;
    always @* begin
        rgb=12'h123;
        tile_color=0; tile_sx=0; tile_sy=0; tile_mark=0;
        board_x=0; board_y=0; board_index=0;
        satellite_x={1'b0,ax_view};
        satellite_y={1'b0,ay_view};
        case(orientation_view)
            0: satellite_y=satellite_y-1;
            1: satellite_x=satellite_x+1;
            2: satellite_y=satellite_y+1;
            3: satellite_x=satellite_x-1;
        endcase
        // Playfield x=[64,255], y=[48,431]. Hidden board rows 0,1 are clipped.
        if(pixel_x>=60 && pixel_x<260 && pixel_y>=44 && pixel_y<436)
            rgb=12'h789;
        if(pixel_x>=64 && pixel_x<256 && pixel_y>=48 && pixel_y<432) begin
            board_x=(pixel_x-64)>>5;
            board_y=((pixel_y-48)>>5)+2;
            board_index=board_y*6+board_x;
            tile_sx=(pixel_x-64)&31;
            tile_sy=(pixel_y-48)&31;
            tile_color=board_view[board_index*3 +: 3];
            tile_mark=clear_view[board_index];
            if(active_view && board_x==ax_view && board_y==ay_view) begin
                tile_color=a_view;
                tile_mark=0;
            end
            if(active_view && board_x==satellite_x && board_y==satellite_y) begin
                tile_color=b_view;
                tile_mark=0;
            end
            rgb=puyo_pixel(tile_color,tile_sx,tile_sy,tile_mark);
            if(tile_sx==0 || tile_sy==0) rgb=12'h234;
        end
        // Next pair uses the exact same renderer and color IDs.
        if(pixel_x>=320 && pixel_x<352 && pixel_y>=306 && pixel_y<370) begin
            tile_sx=pixel_x-320;
            tile_sy=(pixel_y-306)&31;
            tile_color=pixel_y<338 ? nb_view : na_view;
            rgb=puyo_pixel(tile_color,tile_sx,tile_sy,1'b0);
        end
        // One shared font multiplexer. All text is 5x7, magnified 2x.
        text_enable=1; tx=320; ty=32; text_length=9;
        text_line="PUYO SOLO       "; number_kind=0;
        short_bcd=0;
        if(pixel_y>=80 && pixel_y<94) begin
            ty=80; text_length=busy_view?9:4;
            text_line=busy_view?"RESOLVING       ":"PLAY            ";
        end else if(pixel_y>=112 && pixel_y<126) begin
            ty=112; text_length=5; text_line="SCORE           ";
        end else if(pixel_y>=136 && pixel_y<150) begin
            ty=136; text_length=10; number_kind=1;
        end else if(pixel_y>=176 && pixel_y<190) begin
            ty=176; text_length=5; text_line="CHAIN           ";
        end else if(pixel_y>=200 && pixel_y<214) begin
            ty=200; text_length=3; number_kind=2; short_bcd=bcd8(chain_view);
        end else if(pixel_y>=232 && pixel_y<246) begin
            ty=232; text_length=4; text_line="LAST            ";
        end else if(pixel_y>=256 && pixel_y<270) begin
            ty=256; text_length=3; number_kind=2; short_bcd=bcd8(last_view);
        end else if(pixel_y>=282 && pixel_y<296) begin
            ty=282; text_length=4; text_line="NEXT            ";
        end else if(pixel_y>=394 && pixel_y<408) begin
            ty=394; text_length=9; text_line="GAME OVER       "; text_enable=over_view;
        end else if(pixel_y>=418 && pixel_y<432) begin
            ty=418; text_length=13; text_line="RESTART: SW14   ";
        end else if(pixel_y>=452 && pixel_y<466) begin
            tx=64; ty=452; text_length=15; text_line="L/R MOVE D DROP ";
        end else if(!(pixel_y>=32 && pixel_y<46)) text_enable=0;
        // Put the second controls label on the same row, right of first.
        if(pixel_y>=452 && pixel_y<466 && pixel_x>=320) begin
            tx=320; ty=452; text_length=7; text_line="U/C ROT         ";
        end
        text_col=0; font_x=0; font_y=0; character=0; character_bits=0;
        if(text_enable && pixel_x>=tx && pixel_x<tx+text_length*12 &&
           pixel_y>=ty && pixel_y<ty+14) begin
            text_col=(pixel_x-tx)/12;
            font_x=((pixel_x-tx)%12)>>1;
            font_y=(pixel_y-ty)>>1;
            if(number_kind==1) character=8'h30+score_bcd[(9-text_col)*4 +: 4];
            else if(number_kind==2) character=8'h30+short_bcd[(2-text_col)*4 +: 4];
            else character=text_line[(15-text_col)*8 +: 8];
            character_bits=glyph(character);
            if(font_x<5 && character_bits[34-font_y*5-font_x])
                rgb=over_view && ty==394 ? 12'hF67 : 12'hDEF;
        end
        if(pixel_x>=640 || pixel_y>=480) rgb=0;
    end

    always @(posedge clk) begin
        if(reset) begin
            vga_red<=0; vga_green<=0; vga_blue<=0;
            hsync<=1; vsync<=1;
        end else begin
            {vga_red,vga_green,vga_blue}<=rgb;
            hsync<=!(pixel_x>=656 && pixel_x<752);
            vsync<=!(pixel_y>=490 && pixel_y<492);
        end
    end
endmodule
