`timescale 1ns/1ps
`default_nettype none

// Freestanding RV32I C regression harness.
//
// This testbench deliberately instantiates the real CPU core and its real
// synchronous instruction/data memories.  It does not instantiate the game
// engine, video path, or board top.  The compiled test program reports through
// two otherwise-unused words in the external-MMIO window:
//   0x2054: final result (0 = pass, nonzero = failure code)
//   0x2058: optional progress value
module tb_rv32_game_tests #(
    parameter integer WATCHDOG_CYCLES = 10_000_000,
    parameter integer POST_RESULT_CYCLES = 32,
    parameter integer MMIO_WAIT_CYCLES = 3
);
    localparam [31:0] TEST_RESULT_ADDR   = 32'h0000_2054;
    localparam [31:0] TEST_PROGRESS_ADDR = 32'h0000_2058;

    reg         clk;
    reg         reset;
    reg         cpu_enable;
    reg  [7:0]  input_port;
    reg  [4:0]  debug_reg_addr;

    wire [7:0]  output_port;
    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [31:0] debug_reg_data;
    wire [31:0] debug_mem_word0;
    wire [4:0]  debug_trap_cause;
    wire [31:0] debug_trap_value;
    wire        fault;
    wire        retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] retire_instruction;
    wire        mmio_valid;
    wire        mmio_write;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;
    wire        mmio_ready;
    wire [31:0] counter_cycle;
    wire [31:0] counter_instret;
    wire [31:0] counter_mem_stall;
    wire [31:0] counter_load_stall;
    wire [31:0] counter_flush;

    reg  [31:0] mmio_wait_count;
    reg  [31:0] watchdog_count;
    reg  [31:0] observed_mmio_wait_cycles;
    reg  [31:0] accepted_mmio_reads;
    reg  [31:0] accepted_mmio_writes;
    reg  [31:0] result_store_count;
    reg  [31:0] progress_store_count;
    reg  [31:0] last_progress;
    reg  [31:0] result_value;
    reg         result_seen;
    reg  [31:0] post_result_count;

    // Track a delayed request and prove that the CPU holds every bus field
    // stable until the single ready/valid completion edge.
    reg         stalled_request;
    reg         stalled_write;
    reg  [31:0] stalled_addr;
    reg  [31:0] stalled_wdata;

    integer watchdog_limit;

    TD8_RISCV_V31_Core #(
        .IMEM_WORDS(4096),
        .INIT_DEMO(0),
        .IMEM_INIT_FILE("puyo_tests.mem"),
        .DMEM_INIT_FILE("puyo_tests_data.mem"),
        .ENABLE_RF_DEBUG(0),
        .ENABLE_MEM_DEBUG(0)
    ) dut (
        .clk(clk),
        .reset(reset),
        .cpu_enable(cpu_enable),
        .input_port(input_port),
        .debug_reg_addr(debug_reg_addr),
        .output_port(output_port),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_reg_data(debug_reg_data),
        .debug_mem_word0(debug_mem_word0),
        .debug_trap_cause(debug_trap_cause),
        .debug_trap_value(debug_trap_value),
        .fault(fault),
        .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_instruction(retire_instruction),
        .mmio_valid(mmio_valid),
        .mmio_write(mmio_write),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready),
        .counter_cycle(counter_cycle),
        .counter_instret(counter_instret),
        .counter_mem_stall(counter_mem_stall),
        .counter_load_stall(counter_load_stall),
        .counter_flush(counter_flush)
    );

    // 25 MHz, matching the implemented CPU clock in the FPGA system.
    always #20 clk = ~clk;

    // The stub returns zero for every read.  A deterministic wait exercises
    // the same ready/valid hold behavior as a delayed peripheral while keeping
    // the regression reproducible.  Set MMIO_WAIT_CYCLES to zero for an
    // always-ready peripheral.
    assign mmio_ready = (MMIO_WAIT_CYCLES == 0) ||
                        (mmio_wait_count >= MMIO_WAIT_CYCLES);

    assign mmio_rdata = 32'd0;

    always @(posedge clk) begin
        if (reset || !mmio_valid || (mmio_valid && mmio_ready))
            mmio_wait_count <= 32'd0;
        else
            mmio_wait_count <= mmio_wait_count + 32'd1;
    end

    always @(posedge clk) begin
        if (reset) begin
            watchdog_count           <= 32'd0;
            observed_mmio_wait_cycles <= 32'd0;
            accepted_mmio_reads      <= 32'd0;
            accepted_mmio_writes     <= 32'd0;
            result_store_count       <= 32'd0;
            progress_store_count     <= 32'd0;
            last_progress            <= 32'd0;
            result_value             <= 32'd0;
            result_seen              <= 1'b0;
            post_result_count        <= 32'd0;
            stalled_request          <= 1'b0;
            stalled_write            <= 1'b0;
            stalled_addr             <= 32'd0;
            stalled_wdata            <= 32'd0;
        end else begin
            watchdog_count <= watchdog_count + 32'd1;

            if (mmio_valid && !mmio_ready) begin
                observed_mmio_wait_cycles <= observed_mmio_wait_cycles + 32'd1;
                if (!stalled_request) begin
                    stalled_request <= 1'b1;
                    stalled_write   <= mmio_write;
                    stalled_addr    <= mmio_addr;
                    stalled_wdata   <= mmio_wdata;
                end else if ((mmio_write !== stalled_write) ||
                             (mmio_addr !== stalled_addr) ||
                             (mmio_wdata !== stalled_wdata)) begin
                    $fatal(1,
                           "MMIO request changed while stalled: old write=%0d addr=%08x data=%08x, new write=%0d addr=%08x data=%08x",
                           stalled_write, stalled_addr, stalled_wdata,
                           mmio_write, mmio_addr, mmio_wdata);
                end
            end

            if (mmio_valid && mmio_ready) begin
                if (stalled_request &&
                    ((mmio_write !== stalled_write) ||
                     (mmio_addr !== stalled_addr) ||
                     (mmio_wdata !== stalled_wdata))) begin
                    $fatal(1,
                           "MMIO completion differs from stalled request");
                end
                stalled_request <= 1'b0;

                if (mmio_write) begin
                    accepted_mmio_writes <= accepted_mmio_writes + 32'd1;

                    if (mmio_addr == TEST_PROGRESS_ADDR) begin
                        progress_store_count <= progress_store_count + 32'd1;
                        last_progress <= mmio_wdata;
                        $display("[RV32-C] progress=%08x cycle=%0d instret=%0d",
                                 mmio_wdata, counter_cycle, counter_instret);
                    end

                    if (mmio_addr == TEST_RESULT_ADDR) begin
                        if (result_store_count != 0)
                            $fatal(1,
                                   "test-result STORE completed more than once: data=%08x",
                                   mmio_wdata);

                        result_store_count <= result_store_count + 32'd1;
                        result_value       <= mmio_wdata;
                        result_seen        <= 1'b1;

                        if (mmio_wdata != 32'd0)
                            $fatal(1,
                                   "RV32 C tests failed: result=%08x cycle=%0d instret=%0d pc=%08x",
                                   mmio_wdata, counter_cycle,
                                   counter_instret, debug_pc);
                    end
                end else begin
                    accepted_mmio_reads <= accepted_mmio_reads + 32'd1;
                end
            end

            if (fault) begin
                $fatal(1,
                       "CPU fault before successful completion: pc=%08x instruction=%08x cause=%0d value=%08x cycle=%0d instret=%0d",
                       debug_pc, debug_instruction, debug_trap_cause,
                       debug_trap_value, counter_cycle, counter_instret);
            end

            if (result_seen) begin
                if (post_result_count >= POST_RESULT_CYCLES - 1) begin
                    if ((result_store_count != 1) || (result_value != 0))
                        $fatal(1,
                               "invalid final result state: stores=%0d value=%08x",
                               result_store_count, result_value);

                    $display("PASS: tb_rv32_game_tests result=0 cycles=%0d instret=%0d mem_stall=%0d load_stall=%0d flush=%0d mmio_wait=%0d mmio_reads=%0d mmio_writes=%0d progress_writes=%0d last_progress=%08x",
                             counter_cycle, counter_instret,
                             counter_mem_stall, counter_load_stall,
                             counter_flush, observed_mmio_wait_cycles,
                             accepted_mmio_reads, accepted_mmio_writes,
                             progress_store_count, last_progress);
                    $finish;
                end
                post_result_count <= post_result_count + 32'd1;
            end

            if (watchdog_count >= watchdog_limit - 1) begin
                $fatal(1,
                       "watchdog timeout: limit=%0d pc=%08x instruction=%08x cycle=%0d instret=%0d mem_stall=%0d progress=%08x",
                       watchdog_limit, debug_pc, debug_instruction,
                       counter_cycle, counter_instret,
                       counter_mem_stall, last_progress);
            end
        end
    end

    initial begin
        clk            = 1'b0;
        reset          = 1'b1;
        cpu_enable     = 1'b0;
        input_port     = 8'd0;
        debug_reg_addr = 5'd0;
        mmio_wait_count = 32'd0;

        watchdog_limit = WATCHDOG_CYCLES;
        if ($value$plusargs("WATCHDOG=%d", watchdog_limit)) begin
            if (watchdog_limit <= 0)
                $fatal(1, "WATCHDOG must be positive");
        end

        repeat (8) @(posedge clk);
        @(negedge clk);
        reset      = 1'b0;
        cpu_enable = 1'b1;
    end
endmodule

`default_nettype wire
