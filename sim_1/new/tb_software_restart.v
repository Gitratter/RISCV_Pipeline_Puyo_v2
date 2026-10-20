`timescale 1ns/1ps
// Exercise the production (non-fixed-sequence) RV32I ROM through real buttons.
module tb_software_restart;
    reg clk=0, reset=1, restart_button=0;
    always #20 clk=~clk;
    wire [3:0] r,g,b;
    wire hs,vs;
    wire [15:0] leds;
    PuyoSoftwareSystem #(.CLK_HZ(1000000),.DEBOUNCE_MS(2)) dut(
        .clk(clk),.reset(reset),.raw_left(1'b0),.raw_right(1'b0),.raw_down(1'b0),
        .raw_rot_l(1'b0),.raw_rot_r(1'b0),.raw_restart(restart_button),
        .vga_red(r),.vga_green(g),.vga_blue(b),.hsync(hs),.vsync(vs),.led(leds));
    wire [11:0] colors={dut.color_a,dut.color_b,dut.next_a,dut.next_b};
    reg [11:0] first_colors, held_colors;
    integer i, different=0, cycles=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(!reset && dut.fault) $fatal(1,"Normal firmware fault: cause=%0d value=%h",
            dut.cpu.debug_trap_cause,dut.cpu.debug_trap_value);
        if(cycles>3000000) $fatal(1,"Normal restart watchdog");
    end
    task wait_ms(input integer duration);
        reg [31:0] start_ms;
        begin
            start_ms=dut.milliseconds;
            while(dut.milliseconds-start_ms<duration) @(negedge clk);
        end
    endtask
    task check_round;
        begin
            if(!dut.boot || !dut.active_valid || dut.game_over || dut.score!=0 ||
               dut.board!=0 || dut.active_x!=2 || dut.orientation!=0)
                $fatal(1,"Normal restart state not initialized");
            if(dut.color_a<1 || dut.color_a>4 || dut.color_b<1 || dut.color_b>4 ||
               dut.next_a<1 || dut.next_a>4 || dut.next_b<1 || dut.next_b>4)
                $fatal(1,"Invalid production RNG colors");
        end
    endtask
    initial begin
        repeat(8) @(negedge clk); reset=0;
        wait(dut.boot && dut.active_valid); @(negedge clk);
        check_round;
        first_colors=colors;
        for(i=0;i<8;i=i+1) begin
            restart_button=0; wait_ms(12);
            restart_button=1; wait_ms(15);
            check_round;
            if(dut.active_y!=1) $fatal(1,"Spawn y not restored");
            held_colors=colors;
            if(colors!=first_colors) different=different+1;
            wait_ms(50);
            if(colors!==held_colors) $fatal(1,"Held SW14 repeatedly restarted production RNG");
            $display("CHECK normal restart %0d active/NEXT=%03h",i,held_colors);
        end
        if(different==0) $fatal(1,"All restarts replayed identical initial pair and NEXT");
        // A full CPU reset must clear its BSS rather than reuse the previous game.
        restart_button=0; wait_ms(710);
        if(dut.active_y<=1) $fatal(1,"Production 700ms drop did not run");
        reset=1; repeat(8) @(negedge clk); reset=0;
        wait(dut.boot && dut.active_valid); @(negedge clk);
        check_round;
        if(dut.active_y!=1 || dut.chain!=0 || dut.last_chain!=0)
            $fatal(1,"CPU reset did not reinitialize BSS-backed game");
        $display("PASS tb_software_restart: production ROM, 8 session RNG restarts, held switch, 700ms drop, CPU/BSS reset; different=%0d",different);
        $finish;
    end
endmodule
