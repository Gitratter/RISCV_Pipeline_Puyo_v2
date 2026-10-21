# RISCV_Pipeline_Puyo_v2

A Basys 3 FPGA platform that runs a falling-pair puzzle game on a five-stage RV32I processor. The CPU executes the game from an instruction-memory image and publishes the board and display state through MMIO. Hardware provides button conditioning, a millisecond timer, display registers, and VGA output.

Compared with [v1](https://github.com/Gitratter/RISCV_Pipeline_Puyo_v1), this design replaces the dedicated game engine with a software-controlled display interface. There is no `PuyoEngine` module in the design.

## Architecture

```text
Buttons -> Synchronizers and debounce -> Input MMIO
                                             |
Instruction ROM / Data RAM <-> RV32I CPU <-> Display staging registers
                                             |
                                      Publish transaction
                                             |
                                      Frame snapshot -> VGA
```

The Basys 3's 100 MHz oscillator is converted to a 25 MHz system clock by an MMCM. CPU, peripherals, and video share this clock. The CPU uses IF, ID, EX, MEM, and WB stages with forwarding, load-use stalls, and control-flow flushes. Synchronous-memory response tokens hold the pipeline until the required responses arrive.

Instruction ROM is 4096 words (16 KiB), and data RAM is 1024 words (4 KiB). Both have initialization images. The register file uses distributed RAM and a resettable validity mask. The core has trap diagnostics but no privileged CSR interface, interrupts, or trap handler.

VGA has a 640 x 480 visible area and an 800 x 525 total frame. At a 25 MHz pixel clock, the refresh rate is approximately 59.52 Hz. RGB and synchronization signals are registered together.

## Controls

| Board input | Action |
|---|---|
| `btnL` / `btnR` | Move left / right |
| `btnU` | Rotate clockwise |
| `btnC` | Rotate counterclockwise |
| `btnD` | Soft drop |
| SW14, OFF to ON | Restart; return OFF before restarting again |
| SW15 ON | Hold the system in reset |

Hardware debounces the six game inputs; software handles press edges, movement repeat, and game timing. LED15 indicates CPU fault, LED14 game over, LED13 busy, and LED12 firmware boot status. LED11:8 show bits 19:16 of the retired-instruction counter. LED7:0 reflect the CPU's legacy output register. The seven-segment display is disabled.

## Memory map

Instruction and data addresses belong to separate spaces.

| Data range | Function |
|---|---|
| `0x0000`–`0x00ff` | Alias of the first 256 bytes of data RAM |
| `0x0100` | Legacy eight-bit input, tied to zero in this top |
| `0x0104` | Legacy eight-bit output/readback |
| `0x1000`–`0x1fff` | 4 KiB data RAM |
| `0x2000`–`0x20ff` | External MMIO, aligned `LW` / `SW` only |

RAM supports byte, halfword, and word accesses with natural alignment. Invalid accesses trap. CPU reset does not clear the RAM arrays.

### Peripheral registers

| Address | Access | Function |
|---|---|---|
| `0x2000` | R | Stable keys: bits 0..5 = left, right, down, counterclockwise, clockwise, restart |
| `0x2004` | R | Milliseconds since system reset |
| `0x2008` | R | CPU cycle counter |
| `0x200c` | R | Platform ID, `0x50535935` |
| `0x2010` / `0x2014` | R | Frame / publication counters |
| `0x2020` | W | Staging cell index; valid range 0..83 |
| `0x2024` | W | Cell color in bits 2:0 and clear marker in bit 8 |
| `0x2028` | W | Active pair: x[3:0], y[7:4], orientation[9:8], color A[12:10], color B[15:13] |
| `0x202c` | W | Next pair: color A[2:0], color B[5:3] |
| `0x2030` | W | Staged 32-bit score |
| `0x2034` | W | Chain[7:0], last chain[15:8], phase[23:16], active[24], busy[25], game over[26], boot[27] |
| `0x2038` | W | Write bit 0 = 1 to publish all staged fields together |
| `0x2040`–`0x2050` | R | Cycle, retired instructions, memory-wait cycles, load-use bubbles, and flushes, in four-byte steps |

An accepted transfer occurs on a rising edge with `valid && ready`. Out-of-range cell indices are ignored. Reserved reads return zero and reserved writes have no effect. Publication copies the staging state atomically; the video module takes a separate snapshot at vertical blanking.

## FPGA setup

1. Create a Vivado project for the Basys 3 part `xc7a35tcpg236-1`.
2. Add all `.v` files in [sources_1/new](sources_1/new) as design sources.
3. Add `puyo_game.mem` and `puyo_game_data.mem` from that directory as memory initialization files.
4. Add [Basys3_Puyo.xdc](constrs_1/new/Basys3_Puyo.xdc).
5. Select `TD8_RISCV_PUYO_TOP` as the top, with `SIMULATION` unset for synthesis.
6. Run synthesis and implementation and inspect the timing and DRC reports before generating a bitstream.

The repository contains prebuilt game and test memory images. It does not contain firmware source, a linker script, or a firmware build system, so those images cannot be regenerated from this checkout alone. No routed reports or bitstream are included.

## Simulation

There are 17 testbenches: eleven CPU regressions and six tests for the platform, software game, MMIO, restart behavior, and video. With PowerShell, Icarus Verilog, and `vvp` available, run the following from the repository root. The temporary run directory gives `$readmemh` access to all required images.

```powershell
$rtl = (Get-ChildItem ./sources_1/new -Filter *.v | Sort-Object Name).FullName
$sim = (Resolve-Path ./sim_1/new).Path
$tests = Get-ChildItem $sim -Recurse -Filter tb_*.v | Sort-Object FullName
$run = (New-Item -ItemType Directory -Force ./build/readme-sim).FullName
Copy-Item ./sources_1/new/*.mem $run
Copy-Item ./sim_1/new/*.mem $run
Push-Location $run
try {
    foreach ($test in $tests) {
        $out = Join-Path $run ($test.BaseName + '.vvp')
        iverilog -g2012 -Wall -DSIMULATION -I $sim -s $test.BaseName -o $out $rtl $test.FullName
        if ($LASTEXITCODE -ne 0) { throw "Compile failed: $($test.Name)" }
        vvp $out
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $($test.Name)" }
    }
} finally {
    Pop-Location
}
```

`tb_software_system` uses the integration images, while `tb_software_restart` uses the production game images. `tb_rv32_game_tests` runs the compiled test program on the CPU and checks its result through test-only MMIO addresses `0x2054` and `0x2058`; these addresses are not game-platform registers.

Testbench assertions describe the checks performed. Successful simulation, FPGA timing closure, and monitor/button operation are separate verification steps.

## License

[MIT](LICENSE).
