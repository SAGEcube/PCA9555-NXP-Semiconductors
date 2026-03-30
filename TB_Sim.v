// ============================================================
// PCA9555 Testbench  -  Waveform-Optimised Version
// Compatible: Vivado xsim  +  ModelSim (remove $dump lines)
//
// Signals organised for clean waveform presentation:
//   Group A - I2C Bus          : SCL_drv, SDA_bus, SDA_oe, SDA_tb_low
//   Group B - Test Status      : test_num, test_name, pass_cnt, fail_cnt
//   Group C - Port 0           : port0_oe, port0_out, port0_in, port0_ext
//   Group D - Port 1           : port1_oe, port1_out, port1_in, port1_ext
//   Group E - Internal Regs    : config_reg0/1, output_reg0/1,
//                                polarity_reg0/1, input_latch0/1
//   Group F - Interrupt        : int_active
//   Group G - I2C State        : i2c_state (ASCII name of DUT FSM state)
// ============================================================
`timescale 1ns/1ps

module pca9555_tb;

    // --------------------------------------------------------
    // Timing parameters (10 MHz clock, 100 kHz I2C)
    // --------------------------------------------------------
    parameter CLK_HALF = 50;        // 50 ns  -> 10 MHz clock
    parameter HALF     = 5000;      // 5000 ns -> 100 kHz I2C half-period
    parameter QTR      = 2500;
    parameter T_SU     = 1000;      // SDA setup before SCL rise

    parameter [7:0] DEV_WR = 8'h40;   // 0100_000_0
    parameter [7:0] DEV_RD = 8'h41;   // 0100_000_1

    // --------------------------------------------------------
    // DUT connections
    // --------------------------------------------------------
    reg  clk, rst;
    reg  SCL_drv;          // testbench drives SCL
    reg  SDA_tb_low;       // testbench pulls SDA low (open-drain master)
    wire SDA_oe;           // DUT pulls SDA low (open-drain slave)
    wire SDA_bus = (SDA_tb_low | SDA_oe) ? 1'b0 : 1'b1;  // wired-AND

    wire [7:0] port0_oe,  port0_out,  port0_in;
    wire [7:0] port1_oe,  port1_out,  port1_in;
    reg  [7:0] port0_ext, port1_ext;   // external stimulus on input pins
    wire       int_active;

    // --------------------------------------------------------
    // Pin model: output-enable selects between DUT output and
    // external stimulus (simulates open-drain IO with pull)
    // --------------------------------------------------------
    assign port0_in[0] = port0_oe[0] ? port0_out[0] : port0_ext[0];
    assign port0_in[1] = port0_oe[1] ? port0_out[1] : port0_ext[1];
    assign port0_in[2] = port0_oe[2] ? port0_out[2] : port0_ext[2];
    assign port0_in[3] = port0_oe[3] ? port0_out[3] : port0_ext[3];
    assign port0_in[4] = port0_oe[4] ? port0_out[4] : port0_ext[4];
    assign port0_in[5] = port0_oe[5] ? port0_out[5] : port0_ext[5];
    assign port0_in[6] = port0_oe[6] ? port0_out[6] : port0_ext[6];
    assign port0_in[7] = port0_oe[7] ? port0_out[7] : port0_ext[7];
    assign port1_in[0] = port1_oe[0] ? port1_out[0] : port1_ext[0];
    assign port1_in[1] = port1_oe[1] ? port1_out[1] : port1_ext[1];
    assign port1_in[2] = port1_oe[2] ? port1_out[2] : port1_ext[2];
    assign port1_in[3] = port1_oe[3] ? port1_out[3] : port1_ext[3];
    assign port1_in[4] = port1_oe[4] ? port1_out[4] : port1_ext[4];
    assign port1_in[5] = port1_oe[5] ? port1_out[5] : port1_ext[5];
    assign port1_in[6] = port1_oe[6] ? port1_out[6] : port1_ext[6];
    assign port1_in[7] = port1_oe[7] ? port1_out[7] : port1_ext[7];

    // --------------------------------------------------------
    // DUT instantiation
    // --------------------------------------------------------
    pca9555 DUT (
        .clk(clk),  .rst(rst),
        .SCL(SCL_drv), .SDA_in(SDA_bus), .SDA_oe(SDA_oe),
        .A0(1'b0),  .A1(1'b0),  .A2(1'b0),
        .int_active(int_active),
        .port0_oe(port0_oe), .port0_out(port0_out), .port0_in(port0_in),
        .port1_oe(port1_oe), .port1_out(port1_out), .port1_in(port1_in)
    );

    // --------------------------------------------------------
    // Clock generation
    // --------------------------------------------------------
    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    // --------------------------------------------------------
    // GROUP G - I2C FSM state name (for waveform readability)
    // Mirrors the DUT state register as a human-readable string.
    // Add this signal to the waveform as ASCII / string radix.
    // --------------------------------------------------------
    reg [79:0] i2c_state;   // 10 chars x 8 bits
    always @(*) begin
        case (DUT.state)
            4'd0: i2c_state = "IDLE      ";
            4'd1: i2c_state = "GET_ADDR  ";
            4'd2: i2c_state = "ADDR_ACK  ";
            4'd3: i2c_state = "GET_CMD   ";
            4'd4: i2c_state = "CMD_ACK   ";
            4'd5: i2c_state = "GET_DATA  ";
            4'd6: i2c_state = "DATA_ACK  ";
            4'd7: i2c_state = "SEND_DATA ";
            4'd8: i2c_state = "READ_ACK  ";
            4'd9: i2c_state = "WAIT_STOP ";
            default: i2c_state = "UNKNOWN   ";
        endcase
    end

    // --------------------------------------------------------
    // GROUP B - Test tracking signals
    // test_num  : which test (1-8) is currently running
    // test_phase: sub-step within a test (SETUP/CHECK/DONE)
    // --------------------------------------------------------
    reg [3:0]  test_num;
    reg [79:0] test_phase;   // "SETUP   " / "CHECK   " / "DONE    "

    // --------------------------------------------------------
    // GROUP B - Pass / Fail counters
    // --------------------------------------------------------
    integer pass_cnt, fail_cnt;

    // --------------------------------------------------------
    // Check tasks
    // --------------------------------------------------------
    task chk8;
        input [7:0]    got, exp;
        input [8*32:1] lbl;
    begin
        if (got === exp) begin
            pass_cnt = pass_cnt + 1;
            $display("  [PASS] %-32s = %02Xh", lbl, got);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("  [FAIL] %-32s = %02Xh  (expected %02Xh)", lbl, got, exp);
        end
    end
    endtask

    task chk1;
        input          got, exp;
        input [8*32:1] lbl;
    begin
        if (got === exp) begin
            pass_cnt = pass_cnt + 1;
            $display("  [PASS] %-32s = %b", lbl, got);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("  [FAIL] %-32s = %b  (expected %b)", lbl, got, exp);
        end
    end
    endtask

    // --------------------------------------------------------
    // I2C bus task helpers
    // --------------------------------------------------------
    integer bk;
    reg     ack_got;
    reg [7:0] rd0, rd1;

    task do_start;
    begin
        SCL_drv = 1; SDA_tb_low = 0; #(HALF);
        SDA_tb_low = 1;                        // SDA falls while SCL=1 -> START
        #(HALF);
        SCL_drv = 0; #(HALF);
    end
    endtask

    task do_stop;
    begin
        SCL_drv = 0; SDA_tb_low = 1; #(HALF);
        SCL_drv = 1;                           // SCL rises
        #(HALF);
        SDA_tb_low = 0;                        // SDA rises while SCL=1 -> STOP
        #(HALF);
    end
    endtask

    task do_wr;
        input [7:0] d;
        output      ack_o;
    begin
        for (bk = 7; bk >= 0; bk = bk - 1) begin
            SCL_drv = 0; #(T_SU);
            SDA_tb_low = ~d[bk];
            #(HALF - T_SU);
            SCL_drv = 1; #(HALF);
            SCL_drv = 0; #(QTR);
        end
        SDA_tb_low = 0; #(HALF);              // release for ACK
        SCL_drv = 1; #(QTR);
        ack_o = ~SDA_bus;
        #(QTR);
        SCL_drv = 0; #(HALF);
    end
    endtask

    task do_rd;
        input        send_ack;
        output [7:0] d;
    begin
        SDA_tb_low = 0; d = 8'h00;
        for (bk = 7; bk >= 0; bk = bk - 1) begin
            SCL_drv = 0; #(HALF);
            SCL_drv = 1; #(QTR);
            d[bk] = SDA_bus;
            #(QTR);
            SCL_drv = 0; #(QTR);
        end
        SDA_tb_low = send_ack ? 1'b1 : 1'b0;
        #(HALF);
        SCL_drv = 1; #(HALF);
        SCL_drv = 0; SDA_tb_low = 0; #(HALF);
    end
    endtask

    // Write 1 or 2 data bytes after command
    task wr_reg;
        input [7:0] dev, cmd, d0, d1;
        input       two;
    begin
        do_start;
        do_wr(dev, ack_got);
        do_wr(cmd, ack_got);
        do_wr(d0,  ack_got);
        if (two) do_wr(d1, ack_got);
        do_stop;
        #(HALF * 4);
    end
    endtask

    // Write cmd, repeated-START, read 2 bytes
    task rd_reg;
        input  [7:0] dwr, drd, cmd;
        output [7:0] o0, o1;
    begin
        do_start;
        do_wr(dwr, ack_got);
        do_wr(cmd, ack_got);
        // Repeated START
        SCL_drv = 0; SDA_tb_low = 0; #(HALF);
        SCL_drv = 1; #(QTR);
        SDA_tb_low = 1; #(QTR);               // SDA falls = repeated-START
        SCL_drv = 0; #(HALF);
        do_wr(drd, ack_got);
        do_rd(1, o0);
        do_rd(0, o1);
        do_stop;
        #(HALF * 4);
    end
    endtask

    // --------------------------------------------------------
    // VCD dump  (DELETE these 4 lines when moving to ModelSim)
    // --------------------------------------------------------
    initial begin
        $dumpfile("pca9555_tb.vcd");
        $dumpvars(0, pca9555_tb);
    end

    // --------------------------------------------------------
    // Main test sequence
    // --------------------------------------------------------
    initial begin
        // Initialise tracking signals
        pass_cnt   = 0;
        fail_cnt   = 0;
        test_num   = 4'd0;
        test_phase = "INIT      ";

        // Reset sequence
        rst = 1; SCL_drv = 1; SDA_tb_low = 0;
        port0_ext = 8'hFF; port1_ext = 8'hFF;
        repeat(20) @(posedge clk); #1;
        rst = 0;
        repeat(10) @(posedge clk); #1;
        #(HALF * 2);

        $display("");
        $display("##############################################");
        $display("#         PCA9555 SIMULATION RESULTS         #");
        $display("##############################################");

        // ==========================================================
        // TEST 1: Power-On Reset Defaults
        //   Datasheet: all config=FF (inputs), output=FF, polarity=00
        // ==========================================================
        test_num   = 4'd1;
        test_phase = "CHECK     ";
        $display("");
        $display("==============================================");
        $display(" TEST 1: Power-On Reset Defaults");
        $display("==============================================");
        chk8(DUT.config_reg0,   8'hFF, "config_reg0  (expect FF)");
        chk8(DUT.config_reg1,   8'hFF, "config_reg1  (expect FF)");
        chk8(DUT.output_reg0,   8'hFF, "output_reg0  (expect FF)");
        chk8(DUT.output_reg1,   8'hFF, "output_reg1  (expect FF)");
        chk8(DUT.polarity_reg0, 8'h00, "polarity_reg0(expect 00)");
        chk8(DUT.polarity_reg1, 8'h00, "polarity_reg1(expect 00)");
        chk8(port0_oe,          8'h00, "port0_oe     (expect 00)");
        chk8(port1_oe,          8'h00, "port1_oe     (expect 00)");
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 2: Write Configuration Registers
        //   Datasheet cmd 6 = Config Port0, cmd 7 = Config Port1
        //   Bit=1 -> input, Bit=0 -> output  (OE = ~config)
        // ==========================================================
        test_num   = 4'd2;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 2: Write Configuration Registers");
        $display(" cmd=6 -> config0=F0  cmd=7 -> config1=FF");
        $display("==============================================");
        wr_reg(DEV_WR, 8'd6, 8'hF0, 8'hFF, 1'b1);
        test_phase = "CHECK     ";
        chk8(DUT.config_reg0, 8'hF0, "config_reg0  (expect F0)");
        chk8(DUT.config_reg1, 8'hFF, "config_reg1  (expect FF)");
        chk8(port0_oe,        8'h0F, "port0_oe     (expect 0F)");
        chk8(port1_oe,        8'h00, "port1_oe     (expect 00)");
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 3: Write Output Port Registers
        //   Datasheet cmd 2 = Output Port0, cmd 3 = Output Port1
        //   Written value drives pin only when config bit = 0
        // ==========================================================
        test_num   = 4'd3;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 3: Write Output Port Registers");
        $display(" cmd=2 -> out0=05   cmd=3 -> out1=AA");
        $display("==============================================");
        wr_reg(DEV_WR, 8'd2, 8'h05, 8'hAA, 1'b1);
        test_phase = "CHECK     ";
        chk8(DUT.output_reg0, 8'h05, "output_reg0  (expect 05)");
        chk8(DUT.output_reg1, 8'hAA, "output_reg1  (expect AA)");
        chk1(port0_out[0], 1'b1, "IO0_0 HIGH (expect 1)");
        chk1(port0_out[1], 1'b0, "IO0_1 LOW  (expect 0)");
        chk1(port0_out[2], 1'b1, "IO0_2 HIGH (expect 1)");
        chk1(port0_out[3], 1'b0, "IO0_3 LOW  (expect 0)");
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 4: Read Input Port Registers
        //   Datasheet cmd 0 = Input Port0, cmd 1 = Input Port1
        //   Input register always reflects pin state
        // ==========================================================
        test_num   = 4'd4;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 4: Read Input Port Registers");
        $display(" port0_ext=A0  port1_ext=CC");
        $display("==============================================");
        port0_ext = 8'hA0; port1_ext = 8'hCC;
        #(HALF * 4);
        rd_reg(DEV_WR, DEV_RD, 8'd0, rd0, rd1);
        test_phase = "CHECK     ";
        $display("  Port0 read = %02Xh   Port1 read = %02Xh", rd0, rd1);
        chk8(rd0[7:4], 4'hA, "port0[7:4] input (expect A)");
        chk8(rd1,    8'hCC,  "port1 input      (expect CC)");
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 5: Polarity Inversion Register
        //   Datasheet cmd 4 = Polarity Port0, cmd 5 = Polarity Port1
        //   Polarity=1 -> input bit is inverted before reading
        // ==========================================================
        test_num   = 4'd5;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 5: Polarity Inversion");
        $display(" pol0=FF -> read A0 as 5F");
        $display("==============================================");
        wr_reg(DEV_WR, 8'd4, 8'hFF, 8'h00, 1'b1);
        test_phase = "CHECK     ";
        chk8(DUT.polarity_reg0, 8'hFF, "polarity_reg0(expect FF)");
        rd_reg(DEV_WR, DEV_RD, 8'd0, rd0, rd1);
        $display("  Inverted Port0 = %02Xh (upper nibble A->5)", rd0);
        chk8(rd0[7:4], 4'h5, "port0[7:4] inv   (expect 5)");
        test_phase = "SETUP     ";
        wr_reg(DEV_WR, 8'd4, 8'h00, 8'h00, 1'b1);   // restore
        test_phase = "CHECK     ";
        chk8(DUT.polarity_reg0, 8'h00, "polarity_reg0 restored");
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 6: Interrupt Generation and Clearing
        //   Datasheet: INT asserted when input-configured pin changes
        //   Cleared by reading the input port register
        // ==========================================================
        test_num   = 4'd6;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 6: Interrupt Generation and Clearing");
        $display("==============================================");
        wr_reg(DEV_WR, 8'd6, 8'hFF, 8'hFF, 1'b1);   // all pins = inputs
        #(HALF * 4);
        port0_ext = 8'hAA; port1_ext = 8'h55;
        #(HALF * 4);
        rd_reg(DEV_WR, DEV_RD, 8'd0, rd0, rd1);       // latch current state
        #(HALF * 4);
        test_phase = "CHECK     ";
        chk1(int_active, 1'b0, "int_active before change");
        test_phase = "SETUP     ";
        port0_ext[1] = 1'b0;                           // change IO0_1: 1->0
        #(HALF * 4);
        test_phase = "CHECK     ";
        chk1(int_active, 1'b1, "int_active after  change");
        test_phase = "SETUP     ";
        rd_reg(DEV_WR, DEV_RD, 8'd0, rd0, rd1);       // read clears INT
        #(HALF * 4);
        test_phase = "CHECK     ";
        chk1(int_active, 1'b0, "int_active after  clear ");
        test_phase = "SETUP     ";
        port0_ext[1] = 1'b1;                           // restore
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 7: Register Pair Auto-Increment
        //   Datasheet: writing an odd-numbered register auto-pairs
        //   with its even partner in the same transaction
        // ==========================================================
        test_num   = 4'd7;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 7: Register Pair Auto-Increment");
        $display(" Write cmd=3 -> out1=12, auto pair -> out0=34");
        $display("==============================================");
        wr_reg(DEV_WR, 8'd3, 8'h12, 8'h34, 1'b1);
        test_phase = "CHECK     ";
        chk8(DUT.output_reg1, 8'h12, "output_reg1 cmd3  (expect 12)");
        chk8(DUT.output_reg0, 8'h34, "output_reg0 auto2 (expect 34)");
        test_phase = "DONE      ";

        // ==========================================================
        // TEST 8: Output Pin Drive HIGH / LOW
        //   Datasheet: output_reg drives pin when config bit = 0
        //   Verify pin actually changes on the port
        // ==========================================================
        test_num   = 4'd8;
        test_phase = "SETUP     ";
        $display("");
        $display("==============================================");
        $display(" TEST 8: Output Pin Drive HIGH / LOW");
        $display("==============================================");
        wr_reg(DEV_WR, 8'd6, 8'hF0, 8'hFF, 1'b1);   // lower nibble = output
        wr_reg(DEV_WR, 8'd2, 8'hFF, 8'h00, 1'b1);   // drive all HIGH
        #(HALF * 2);
        test_phase = "CHECK     ";
        chk1(port0_out[0], 1'b1, "IO0_0 HIGH (expect 1)");
        chk1(port0_out[1], 1'b1, "IO0_1 HIGH (expect 1)");
        chk1(port0_oe[0],  1'b1, "port0_oe[0] output (expect 1)");
        test_phase = "SETUP     ";
        wr_reg(DEV_WR, 8'd2, 8'h00, 8'h00, 1'b1);   // drive all LOW
        #(HALF * 2);
        test_phase = "CHECK     ";
        chk1(port0_out[0], 1'b0, "IO0_0 LOW  (expect 0)");
        chk1(port0_out[1], 1'b0, "IO0_1 LOW  (expect 0)");
        test_phase = "DONE      ";

        // ==========================================================
        // FINAL SUMMARY
        // ==========================================================
        test_num   = 4'd0;
        test_phase = "SUMMARY   ";
        $display("");
        $display("##############################################");
        $display("#              FINAL SUMMARY                 #");
        $display("##############################################");
        $display("  Total PASS : %0d", pass_cnt);
        $display("  Total FAIL : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  RESULT     : *** ALL TESTS PASSED ***");
        else
            $display("  RESULT     : *** %0d TEST(S) FAILED ***", fail_cnt);
        $display("##############################################");
        #10000;
        $finish;
    end

    // --------------------------------------------------------
    // Timeout guard (25 ms covers all 8 tests comfortably)
    // --------------------------------------------------------
    initial begin
        #25_000_000;
        $display("TIMEOUT - simulation did not finish in 25 ms");
        $finish;
    end

endmodule