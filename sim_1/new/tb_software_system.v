`timescale 1ns/1ps
`default_nettype none
// Integration of the real RV32I game program, CPU BRAMs, physical-input
// conditioning, MMIO publication and the unchanged VGA renderer.
// GAME_FIXED_TEST/GAME_FAST_TEST images are required. CLK_HZ is intentionally
// reduced for the timer: 1000 physical clocks represent one software ms.
// No game-state RAM is written or inspected by this testbench.
module tb_software_system;
    reg clk=0,reset=1;
    always #20 clk=~clk;
    reg left_button=0,right_button=0,down_button=0;
    reg rot_left=0,rot_right=0,restart_button=0;
    wire [3:0] red,green,blue;
    wire hs,vs;
    wire [15:0] leds;
    PuyoSoftwareSystem #(.CLK_HZ(1000000),.DEBOUNCE_MS(2),
        .IMEM_INIT_FILE("puyo_integration.mem"),
        .DMEM_INIT_FILE("puyo_integration_data.mem")) dut(
        .clk(clk),.reset(reset),.raw_left(left_button),.raw_right(right_button),
        .raw_down(down_button),.raw_rot_l(rot_left),.raw_rot_r(rot_right),
        .raw_restart(restart_button),.vga_red(red),.vga_green(green),.vga_blue(blue),
        .hsync(hs),.vsync(vs),.led(leds));

    wire [417:0] published_picture={dut.board,dut.clear_mask,
        dut.color_b,dut.color_a,dut.orientation,dut.active_y,dut.active_x,
        dut.next_b,dut.next_a,dut.score,dut.boot,dut.game_over,dut.busy,
        dut.active_valid,dut.phase,dut.last_chain,dut.chain};
    reg [417:0] frozen_picture;
    reg [31:0] frozen_publish,frozen_retired,start_ms,start_publish;
    reg [3:0] old_x,old_y;
    reg [2:0] expected_next_a,expected_next_b;
    integer cycles=0,video_snapshots=0,nonblack_pixels=0;
    integer recenter;
    reg [251:0] frame_board;
    reg [83:0] frame_mask;
    reg frame_active;
    reg [3:0] frame_x,frame_y;
    reg [1:0] frame_orientation;

    // Independent watchdog and fault monitor also cover every wait below.
    always @(posedge clk) begin
        #1;
        if(!reset) begin
            cycles=cycles+1;
            if(dut.fault)
                $fatal(1,"CPU fault: cause=%0d value=%h pc=%h",
                    dut.cpu.debug_trap_cause,dut.cpu.debug_trap_value,dut.cpu.debug_pc);
            if(cycles>=5000000)
                $fatal(1,"system watchdog: ms=%0d publish=%0d phase=%0d x/y=%0d/%0d pc=%h",
                    dut.milliseconds,dut.peripherals.publish_counter,dut.phase,
                    dut.active_x,dut.active_y,dut.cpu.debug_pc);
            if({red,green,blue}!=0) nonblack_pixels=nonblack_pixels+1;
        end
    end

    // Check the actual frame copy against the published input at that edge.
    // A simultaneous CPU commit may update the public copy after this edge;
    // scanout correctly uses the complete previous published picture then.
    always @(posedge clk) begin
        if(!reset && dut.video.pixel_x==0 && dut.video.pixel_y==480) begin
            frame_board=dut.board; frame_mask=dut.clear_mask;
            frame_active=dut.active_valid; frame_x=dut.active_x;
            frame_y=dut.active_y; frame_orientation=dut.orientation;
            #1;
            if(dut.video.board_view!==frame_board || dut.video.clear_view!==frame_mask ||
               dut.video.active_view!==frame_active || dut.video.ax_view!==frame_x ||
               dut.video.ay_view!==frame_y || dut.video.orientation_view!==frame_orientation)
                $fatal(1,"VGA did not capture the CPU-published picture atomically");
            video_snapshots=video_snapshots+1;
        end
    end

    task wait_ms;
        input [31:0] duration;
        reg [31:0] began;
        begin
            began=dut.milliseconds;
            while((dut.milliseconds-began)<duration) begin @(posedge clk); #2; end
            @(negedge clk);
        end
    endtask
    task tap_left;
        begin
            @(negedge clk); left_button=1;
            wait_ms(20);
            left_button=0;
            wait_ms(12);
        end
    endtask

    initial begin
        repeat(8) @(negedge clk); reset=0;
        wait(dut.boot && dut.active_valid && dut.phase==8'd2);
        @(negedge clk);
        if(dut.board!==0 || dut.score!==0 || dut.active_x!==2 || dut.active_y!==1 ||
           dut.orientation!==0 || dut.color_a!==1 || dut.color_b!==2 ||
           dut.next_a!==3 || dut.next_b!==4 || dut.retired==0)
            $fatal(1,"actual C firmware did not boot into the fixed initial pair");
        expected_next_a=dut.next_a; expected_next_b=dut.next_b;
        $display("CHECK software boot: cycles=%0d publish=%0d",cycles,dut.peripherals.publish_counter);

        // Stop the instruction machine, leaving time, input and VGA running.
        // A hidden RTL game engine would still move during this interval.
        force dut.cpu.cpu_enable=1'b0;
        #1;
        frozen_picture=published_picture;
        frozen_publish=dut.peripherals.publish_counter;
        frozen_retired=dut.retired;
        old_y=dut.active_y;
        start_ms=dut.milliseconds;
        wait_ms(240); // Two automatic-fall periods in the integration image.
        if(published_picture!==frozen_picture || dut.peripherals.publish_counter!==frozen_publish ||
           dut.retired!==frozen_retired || (dut.milliseconds-start_ms)<240)
            $fatal(1,"CPU pause did not freeze software game while timer advanced");
        release dut.cpu.cpu_enable;
        wait_ms(30);
        if(dut.peripherals.publish_counter<=frozen_publish || dut.retired<=frozen_retired ||
           dut.active_y<=old_y)
            $fatal(1,"CPU release did not resume publication and automatic fall");
        $display("CHECK physics pauses with CPU and resumes on CPU release");

        old_x=dut.active_x;
        tap_left;
        if(dut.active_x!==old_x-1 || dut.orientation!==0)
            $fatal(1,"press/release before DAS did not move exactly one cell");
        old_x=dut.active_x;
        wait_ms(20);
        if(dut.active_x!==old_x) $fatal(1,"released left button continued moving");

        @(negedge clk); right_button=1;
        wait_ms(75);
        right_button=0; wait_ms(12);
        if(dut.active_x<old_x+2 || dut.active_x>5)
            $fatal(1,"firmware DAS/ARR did not repeat a held direction");
        $display("CHECK one-cell press/release and software DAS/ARR");

        // Recenter away from the right wall before testing held clockwise rotation.
        for(recenter=0;recenter<3;recenter=recenter+1)
            if(dut.active_x>2) tap_left;
        if(dut.active_x!==2) $fatal(1,"could not recenter active pair");
        @(negedge clk); rot_right=1;
        wait_ms(90); // Longer than DAS and multiple ARR periods; rotation is edge-only.
        if(dut.orientation!==1) $fatal(1,"held rotation repeated or was not accepted");
        rot_right=0; wait_ms(12);
        if(dut.orientation!==1) $fatal(1,"rotation changed on release");
        if(dut.color_a!==1 || dut.color_b!==2 || dut.board!==0)
            $fatal(1,"first pair unexpectedly locked before soft-drop test");
        $display("CHECK held rotation produces exactly one turn");

        @(negedge clk); down_button=1;
        wait(dut.board!=0);
        wait(dut.active_valid && dut.phase==8'd2 &&
             dut.color_a==expected_next_a && dut.color_b==expected_next_b);
        @(negedge clk); down_button=0;
        if(dut.board===0 || dut.game_over || dut.next_a!==2 || dut.next_b!==2)
            $fatal(1,"soft drop/locking or exact NEXT-to-spawn transition failed");
        wait_ms(12);
        $display("CHECK soft-drop lock and NEXT pair becomes the actual pair");

        // Restart is a software edge, not a level-sensitive hardware reset.
        @(negedge clk); restart_button=1;
        wait(dut.board==0 && dut.score==0 && dut.color_a==1 && dut.color_b==2 &&
             dut.active_valid && dut.orientation==0 && dut.active_x==2);
        @(negedge clk);
        if(dut.chain!==0 || dut.last_chain!==0 || dut.game_over || dut.clear_mask!==0)
            $fatal(1,"software restart did not clear published round state");
        start_publish=dut.peripherals.publish_counter;
        wait_ms(200);
        if(dut.board!==0 || dut.score!==0 || dut.active_y<=1 ||
           dut.peripherals.publish_counter<=start_publish || !dut.active_valid)
            $fatal(1,"held restart repeatedly reset the round or stopped software execution");
        restart_button=0; wait_ms(12);
        // Re-arm the physical switch and verify a second software restart.
        restart_button=1;
        wait(dut.active_y==1 && dut.board==0 && dut.active_valid);
        @(negedge clk); restart_button=0;
        $display("CHECK SW14 restart, held-switch suppression, and OFF/ON re-arm");

        if(video_snapshots==0) begin
            wait(video_snapshots!=0); @(negedge clk);
        end
        if(nonblack_pixels==0 || dut.peripherals.frame_counter==0)
            $fatal(1,"VGA frame or visible output missing");
        $display("PASS tb_software_system: actual RV32I C boot/game/input/restart/NEXT, CPU pause proof, published VGA snapshots=%0d, cycles=%0d",video_snapshots,cycles);
        $finish;
    end
endmodule
`default_nettype wire
