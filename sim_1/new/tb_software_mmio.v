`timescale 1ns/1ps
module tb_software_mmio;
    reg clk=0,reset=1,tick_ms=0;
    always #5 clk=~clk;
    reg [5:0] raw_keys=0;
    wire [5:0] keys;
    PuyoButtons #(.DEBOUNCE_MS(3)) controls(
        .clk(clk),.reset(reset),.tick_ms(tick_ms),
        .raw_left(raw_keys[0]),.raw_right(raw_keys[1]),.raw_down(raw_keys[2]),
        .raw_rot_l(raw_keys[3]),.raw_rot_r(raw_keys[4]),.raw_restart(raw_keys[5]),
        .stable_keys(keys));
    reg valid=0,wr=0,frame_tick=0;
    reg [31:0] address=0,write_data=0;
    wire ready;
    wire [31:0] read_data,score;
    wire [251:0] board;
    wire [83:0] mask;
    wire [3:0] ax,ay;
    wire [1:0] orientation;
    wire [2:0] ca,cb,na,nb;
    wire [7:0] chain,last_chain,phase;
    wire active,busy,over,boot;
    PuyoSoftwareMMIO dut(
        .clk(clk),.reset(reset),.valid(valid),.write(wr),.address(address),.write_data(write_data),
        .ready(ready),.read_data(read_data),.stable_keys(keys),.milliseconds(32'd12345),
        .frame_tick(frame_tick),.counter_cycle(32'h12345678),.counter_instret(32'd100),
        .counter_mem_stall(32'd200),.counter_load_stall(32'd300),.counter_flush(32'd400),
        .board_flat(board),.clear_mask(mask),.active_x(ax),.active_y(ay),.orientation(orientation),
        .color_a(ca),.color_b(cb),.next_a(na),.next_b(nb),.score(score),.chain(chain),
        .last_chain(last_chain),.phase(phase),.active_valid(active),.busy(busy),.game_over(over),.boot(boot));

    task store;
        input [31:0] a,d;
        begin
            @(negedge clk); address=a; write_data=d; valid=1; wr=1;
            #1; if(!ready) $fatal(1,"MMIO write unexpectedly not ready");
            @(posedge clk); #1;
            @(negedge clk); valid=0; wr=0;
        end
    endtask
    task expect_read;
        input [31:0] a,expected;
        begin
            @(negedge clk); address=a; valid=1; wr=0;
            #1;
            if(!ready || read_data!==expected)
                $fatal(1,"MMIO read %h expected %h got %h",a,expected,read_data);
            @(negedge clk); valid=0;
        end
    endtask
    task ms;
        input integer count;
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                repeat(4) @(negedge clk);
                tick_ms=1;
                @(negedge clk); tick_ms=0;
                repeat(3) @(negedge clk);
            end
        end
    endtask
    task expect_first_picture;
        begin
            if(board[2:0]!==3'd1 || board[249 +: 3]!==3'd4 || board[248:3]!==0 ||
               mask!==84'd1 || ax!==4'd2 || ay!==4'd3 || orientation!==2'd1 ||
               ca!==3'd3 || cb!==3'd4 || na!==3'd2 || nb!==3'd3 || score!==32'd123456 ||
               chain!==8'd2 || last_chain!==8'h22 || phase!==8'h55 ||
               active!==1 || busy!==0 || over!==1 || boot!==1)
                $fatal(1,"published picture fields are not the expected complete snapshot");
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);
        if(ready!==0 || board!==0 || mask!==0 || score!==0 || keys!==0)
            $fatal(1,"reset not clearing display/input state");
        reset=0;
        expect_read(32'h200c,32'h50535935);
        expect_read(32'h2004,32'd12345);
        expect_read(32'h2008,32'h12345678);
        expect_read(32'h2040,32'h12345678);
        expect_read(32'h2044,32'd100);
        expect_read(32'h2048,32'd200);
        expect_read(32'h204c,32'd300);
        expect_read(32'h2050,32'd400);
        expect_read(32'h20fc,0);
        expect_read(32'h2010,0);
        expect_read(32'h2014,0);

        // A staging write cannot affect any published field before commit.
        store(32'h2020,0); store(32'h2024,32'h101);
        store(32'h2020,83); store(32'h2024,4);
        store(32'h2028,{16'd0,3'd4,3'd3,2'd1,4'd3,4'd2});
        store(32'h202c,{26'd0,3'd3,3'd2});
        store(32'h2030,123456);
        store(32'h2034,32'h0d552202);
        if(board!==0 || mask!==0 || ax!==0 || ay!==0 || orientation!==0 ||
           ca!==0 || cb!==0 || na!==0 || nb!==0 || score!==0 || chain!==0 ||
           last_chain!==0 || phase!==0 || active!==0 || busy!==0 || over!==0 || boot!==0)
            $fatal(1,"partial staging became visible");
        store(32'h2038,0);
        expect_read(32'h2014,0);
        if(board!==0) $fatal(1,"zero commit published a picture");
        // Commit and frame tick must each advance their own counter once.
        @(negedge clk); frame_tick=1; address=32'h2038; write_data=1; valid=1; wr=1;
        @(posedge clk); #1;
        expect_first_picture;
        @(negedge clk); frame_tick=0; valid=0; wr=0;
        expect_read(32'h2010,1); expect_read(32'h2014,1);

        // Guard both immediate out-of-range indices and high-bit aliases.
        store(32'h2020,84); store(32'h2024,32'h107);
        store(32'h2020,128); store(32'h2024,32'h107);
        store(32'h2020,32'h10000); store(32'h2024,32'h107);
        store(32'h2020,32'hffffffff); store(32'h2024,32'h107);
        store(32'h2038,1);
        expect_first_picture;
        expect_read(32'h2014,2);

        // A second partial update leaves the first published picture intact.
        store(32'h2020,0); store(32'h2024,2);
        store(32'h2030,999); expect_first_picture;
        store(32'h2038,1);
        if(board[2:0]!==3'd2 || mask[0]!==0 || score!==999 || board[249 +: 3]!==4)
            $fatal(1,"second atomic update or retained stage field incorrect");
        expect_read(32'h2014,3);
        store(32'h200c,0); store(32'h20fc,32'hffffffff);
        expect_read(32'h200c,32'h50535935); expect_read(32'h2014,3);

        // Raw keys expose stable levels only: no read-to-clear, repeat or edge hardware.
        raw_keys=6'b111111; ms(1); raw_keys=0; ms(1);
        raw_keys=6'b111111; ms(2); raw_keys=0; ms(3);
        expect_read(32'h2000,0);
        raw_keys=6'b111111; ms(3);
        expect_read(32'h2000,63); ms(20); expect_read(32'h2000,63);
        expect_read(32'h2000,63); // Reading levels does not consume a press.
        raw_keys=6'b101010; ms(3); expect_read(32'h2000,42);
        raw_keys=0; ms(3); expect_read(32'h2000,0);

        // Reset clears staging as well as published outputs and both counters.
        store(32'h2030,32'hffffffff);
        @(negedge clk); reset=1; valid=1; wr=1; address=32'h2038; write_data=1;
        #1; if(ready!==0) $fatal(1,"reset must suppress accepted MMIO transfers");
        @(posedge clk); #1;
        if(board!==0 || mask!==0 || score!==0 || active!==0 || boot!==0 || keys!==0)
            $fatal(1,"reset failed after published frame");
        @(negedge clk); reset=0; valid=0; wr=0;
        expect_read(32'h2010,0); expect_read(32'h2014,0);
        store(32'h2038,1);
        if(board!==0 || mask!==0 || score!==0 || boot!==0)
            $fatal(1,"reset left stale staging data");
        $display("PASS tb_software_mmio: stable keys/debounce, atomic publication, staging isolation, index guards, counters, reset");
        $finish;
    end
    initial begin #1000000; $fatal(1,"tb_software_mmio timeout"); end
endmodule
