`timescale 1ns/1ps
module tb_video;
    reg clk=0,reset=1;
    always #20 clk=~clk;
    reg [251:0] board=0;
    reg [83:0] mask=0;
    wire [3:0] red,green,blue;
    wire hs,vs,frame;
    PuyoVideo dut(.clk(clk),.reset(reset),.board_flat(board),
        .active_valid(1'b1),.active_x(4'd2),.active_y(4'd3),.orientation(2'd1),
        .color_a(3'd3),.color_b(3'd4),.next_a(3'd1),.next_b(3'd2),
        .score(32'hFFFFFFFF),.chain(8'd12),.last_chain(8'd123),
        .game_over(1'b1),.busy(1'b1),.clear_mask(mask),
        .vga_red(red),.vga_green(green),.vga_blue(blue),
        .hsync(hs),.vsync(vs),.frame_tick(frame));
    integer n,x,y,hs_low,vs_low,visible,ticks,checks,decimal_value;
    reg [11:0] decimal_expected;
    integer ppm;
    reg [11:0] rgb;
    reg changed;
    initial begin
        for(decimal_value=0;decimal_value<256;decimal_value=decimal_value+1) begin
            decimal_expected=((decimal_value/100)<<8)|(((decimal_value/10)%10)<<4)|(decimal_value%10);
            if(dut.bcd8(decimal_value[7:0])!==decimal_expected)
                $fatal(1,"chain decimal conversion failed for %0d",decimal_value);
        end
        board[(2*6+0)*3 +: 3]=1;
        board[(2*6+1)*3 +: 3]=2;
        board[(2*6+2)*3 +: 3]=4;
        mask[2*6+2]=1;
        // Hidden row must not be shifted into the visible playfield.
        board[0 +: 3]=3;
        repeat(5) @(negedge clk); reset=0;
        wait(frame); @(negedge clk);
        repeat(40) @(negedge clk);
        if(dut.score_bcd!==40'h4294967295) $fatal(1,"score decimal conversion failed");
        while(!(dut.pixel_x==0 && dut.pixel_y==0)) @(negedge clk);
        hs_low=0; vs_low=0; visible=0; ticks=0; checks=0; changed=0;
        ppm=0;
        if($test$plusargs("PPM")) begin
            ppm=$fopen("puyo_video.ppm","w");
            if(!ppm) $fatal(1,"cannot open PPM output");
            $fwrite(ppm,"P3\n640 480\n255\n");
        end
        for(n=0;n<800*525;n=n+1) begin
            x=dut.pixel_x; y=dut.pixel_y;
            if(x==0 && y==100) begin
                board[(2*6+0)*3 +: 3]=4;
                changed=1;
            end
            @(posedge clk); #1;
            rgb={red,green,blue};
            if(hs!==!(x>=656 && x<752)) $fatal(1,"HS timing at %0d,%0d",x,y);
            if(vs!==!(y>=490 && y<492)) $fatal(1,"VS timing at %0d,%0d",x,y);
            if(!hs) hs_low=hs_low+1;
            if(!vs) vs_low=vs_low+1;
            if(frame) ticks=ticks+1;
            if(x<640 && y<480) begin
                visible=visible+1;
                if(ppm) $fwrite(ppm,"%0d %0d %0d\n",red*17,green*17,blue*17);
            end else if(rgb!==0) $fatal(1,"nonblack blanking at %0d,%0d",x,y);
            if(changed && y<480 && dut.board_view[(2*6+0)*3 +: 3]!==3'd1)
                $fatal(1,"snapshot changed inside visible frame");
            if(x==80 && y==64) begin
                if(rgb!==12'hF45) $fatal(1,"red visible tile/hidden-row clipping"); checks=checks+1;
            end
            if(x==112 && y==64) begin
                if(rgb!==12'h4E6) $fatal(1,"green visible tile"); checks=checks+1;
            end
            if(x==144 && y==64) begin
                if(rgb!==12'hFFF) $fatal(1,"clear mask highlight"); checks=checks+1;
            end
            if(x==144 && y==96) begin
                if(rgb!==12'h49F) $fatal(1,"active pivot"); checks=checks+1;
            end
            if(x==176 && y==96) begin
                if(rgb!==12'hFD4) $fatal(1,"active satellite"); checks=checks+1;
            end
            if(x==336 && y==322) begin
                if(rgb!==12'h4E6) $fatal(1,"next satellite"); checks=checks+1;
            end
            if(x==336 && y==354) begin
                if(rgb!==12'hF45) $fatal(1,"next pivot"); checks=checks+1;
            end
            @(negedge clk);
        end
        if(ppm) $fclose(ppm);
        if(hs_low!=50400 || vs_low!=1600 || visible!=307200 || ticks!=1)
            $fatal(1,"full frame counts: HS %0d VS %0d visible %0d tick %0d",hs_low,vs_low,visible,ticks);
        if(checks!=7) $fatal(1,"pixel checks missing");
        if(dut.board_view[(2*6+0)*3 +: 3]!==3'd4) $fatal(1,"new snapshot missing at blank");
        $display("PASS tb_video: 800x525, sync widths, blank RGB, frame snapshot, BCD max uint32 and all uint8 values, seven palette/overlay pixels");
        $finish;
    end
    initial begin #40000000; $fatal(1,"tb_video timeout"); end
endmodule
