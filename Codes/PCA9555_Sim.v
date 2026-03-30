`timescale 1ns/1ps

module pca9555 (
    input  wire        clk,
    input  wire        rst,
    input  wire        SCL,
    input  wire        SDA_in,
    output reg         SDA_oe,
    input  wire        A0, A1, A2,
    output wire        int_active,
    output wire [7:0]  port0_oe,
    output wire [7:0]  port0_out,
    input  wire [7:0]  port0_in,
    output wire [7:0]  port1_oe,
    output wire [7:0]  port1_out,
    input  wire [7:0]  port1_in
);

    // --------------------------------------------------------
    // Internal registers
    // --------------------------------------------------------
    reg [7:0] config_reg0;
    reg [7:0] config_reg1;
    reg [7:0] output_reg0;
    reg [7:0] output_reg1;
    reg [7:0] polarity_reg0;
    reg [7:0] polarity_reg1;
    reg [7:0] input_latch0;
    reg [7:0] input_latch1;

    // --------------------------------------------------------
    // Port output assignments
    // --------------------------------------------------------
    assign port0_oe  = ~config_reg0;   // config=1 -> input (oe=0)
    assign port1_oe  = ~config_reg1;
    assign port0_out = output_reg0;
    assign port1_out = output_reg1;

    // Input with polarity inversion (combinational)
    wire [7:0] input_reg0 = port0_in ^ polarity_reg0;
    wire [7:0] input_reg1 = port1_in ^ polarity_reg1;

    // Fixed device address (A0=A1=A2=0 -> 0b0100_000)
    wire [6:0] DEV_ADDR = 7'b0100000
`timescale 1ns/1ps

module pca9555 (
    input  wire        clk,
    input  wire        rst,
    input  wire        SCL,
    input  wire        SDA_in,
    output reg         SDA_oe,
    input  wire        A0, A1, A2,
    output wire        int_active,
    output wire [7:0]  port0_oe,
    output wire [7:0]  port0_out,
    input  wire [7:0]  port0_in,
    output wire [7:0]  port1_oe,
    output wire [7:0]  port1_out,
    input  wire [7:0]  port1_in
);

    // --------------------------------------------------------
    // Internal registers
    // --------------------------------------------------------
    reg [7:0] config_reg0;
    reg [7:0] config_reg1;
    reg [7:0] output_reg0;
    reg [7:0] output_reg1;
    reg [7:0] polarity_reg0;
    reg [7:0] polarity_reg1;
    reg [7:0] input_latch0;
    reg [7:0] input_latch1;

    // --------------------------------------------------------
    // Port output assignments
    // --------------------------------------------------------
    assign port0_oe  = ~config_reg0;   // config=1 -> input (oe=0)
    assign port1_oe  = ~config_reg1;
    assign port0_out = output_reg0;
    assign port1_out = output_reg1;

    // Input with polarity inversion (combinational)
    wire [7:0] input_reg0 = port0_in ^ polarity_reg0;
    wire [7:0] input_reg1 = port1_in ^ polarity_reg1;

    // Fixed device address (A0=A1=A2=0 -> 0b0100_000)
    wire [6:0] DEV_ADDR = 7'b0100000;

    // --------------------------------------------------------
    // Interrupt (Fix 2): asserted when an input-configured pin
    // changes vs the last latched value. Latch is refreshed
    // only in READ_ACK so the flag stays high until master reads.
    // --------------------------------------------------------
    assign int_active =
        (|((port0_in ^ input_latch0) & config_reg0)) |
        (|((port1_in ^ input_latch1) & config_reg1));

    // --------------------------------------------------------
    // State encoding
    // --------------------------------------------------------
    localparam [3:0]
        IDLE      = 4'd0,
        GET_ADDR  = 4'd1,
        ADDR_ACK  = 4'd2,
        GET_CMD   = 4'd3,
        CMD_ACK   = 4'd4,
        GET_DATA  = 4'd5,
        DATA_ACK  = 4'd6,
        SEND_DATA = 4'd7,
        READ_ACK  = 4'd8,
        WAIT_STOP = 4'd9;

    // --------------------------------------------------------
    // Two-stage synchroniser for SCL and SDA
    // --------------------------------------------------------
    reg scl_d, scl_dd;
    reg sda_d, sda_dd;

    always @(posedge clk) begin
        scl_d  <= SCL;
        scl_dd <= scl_d;
        sda_d  <= SDA_in;
        sda_dd <= sda_d;
    end

    wire scl      = scl_dd;
    wire sda      = sda_dd;
    wire scl_rise = (scl_d == 1'b1 && scl_dd == 1'b0);
    wire scl_fall = (scl_d == 1'b0 && scl_dd == 1'b1);

    // --------------------------------------------------------
    // START / STOP condition detection
    // SDA changes while SCL is (and stays) high.
    //
    // Fix 8: gate stop_det on !scl_fall.
    //   When the master simultaneously drops SCL and releases
    //   SDA (end of ACK clock), scl_fall=1 on the same cycle
    //   that sda_d rises. Without the gate this matches
    //   stop_det and spuriously resets the DUT. Real STOPs
    //   always have SCL stably high so scl_fall=0.
    // --------------------------------------------------------
    reg scl_high;
    always @(posedge clk) begin
        if      (scl == 1'b1) scl_high <= 1'b1;
        else if (scl == 1'b0) scl_high <= 1'b0;
    end

    wire start_det = scl_high && (scl == 1'b1)
                     && (sda_d == 1'b0) && (sda_dd == 1'b1);
    wire stop_det  = scl_high && (scl == 1'b1)
                     && (sda_d == 1'b1) && (sda_dd == 1'b0)
                     && !scl_fall;          // Fix 8

    // --------------------------------------------------------
    // State machine registers
    // ack_phase is dual-purpose:
    //   In ADDR_ACK / CMD_ACK / DATA_ACK:
    //     0 = first scl_fall  (assert ACK)
    //     1 = second scl_fall (release + transition)   [Fix 1]
    //   In READ_ACK:
    //     0 = not yet armed  (ignore any scl_rise)
    //     1 = armed after scl_fall (sample ACK/NACK)   [Fix 7]
    // --------------------------------------------------------
    reg [3:0] state;
    reg [2:0] bit_count;
    reg [7:0] shift_reg;
    reg [7:0] data_reg;
    reg [2:0] cmd_reg;
    reg       rw_bit;
    reg       ack_phase;

    // --------------------------------------------------------
    // TX mux: register selected by cmd_reg (combinational)
    // --------------------------------------------------------
    reg [7:0] tx_data;
    always @(*) begin
        case (cmd_reg)
            3'd0: tx_data = input_reg0;
            3'd1: tx_data = input_reg1;
            3'd2: tx_data = output_reg0;
            3'd3: tx_data = output_reg1;
            3'd4: tx_data = polarity_reg0;
            3'd5: tx_data = polarity_reg1;
            3'd6: tx_data = config_reg0;
            3'd7: tx_data = config_reg1;
            default: tx_data = 8'h00;
        endcase
    end

    // --------------------------------------------------------
    // Main state machine
    // --------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            config_reg0   <= 8'hFF;
            config_reg1   <= 8'hFF;
            output_reg0   <= 8'hFF;
            output_reg1   <= 8'hFF;
            polarity_reg0 <= 8'h00;
            polarity_reg1 <= 8'h00;
            input_latch0  <= 8'hFF;
            input_latch1  <= 8'hFF;
            SDA_oe        <= 1'b0;
            bit_count     <= 3'd7;
            shift_reg     <= 8'h00;
            cmd_reg       <= 3'd0;
            ack_phase     <= 1'b0;
        end else begin

            // Fix 2: no continuous latch update here.
            // Latch is updated ONLY inside READ_ACK on scl_rise.

            case (state)

                // --------------------------------------------
                IDLE: begin
                    SDA_oe    <= 1'b0;
                    bit_count <= 3'd7;
                    shift_reg <= 8'h00;
                    ack_phase <= 1'b0;
                    if (start_det) state <= GET_ADDR;
                end

                // --------------------------------------------
                // Receive 8-bit address + R/W
                // --------------------------------------------
                GET_ADDR: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda};
                        if (bit_count == 3'd0) begin
                            data_reg  <= {shift_reg[6:0], sda};
                            state     <= ADDR_ACK;
                            ack_phase <= 1'b0;
                        end else begin
                            bit_count <= bit_count - 3'd1;
                        end
                    end
                end

                // --------------------------------------------
                // Address ACK
                // Fix 1: ack_phase 0->1st fall, 1->2nd fall
                // Fix 6: on 2nd fall in read mode, drive MSB
                //        immediately (bit_count starts at 6)
                // --------------------------------------------
                ADDR_ACK: begin
                    if (scl_fall) begin
                        if (!ack_phase) begin
                            // 1st fall: pull SDA low = ACK
                            SDA_oe    <= 1'b1;
                            ack_phase <= 1'b1;
                        end else begin
                            // 2nd fall: release and branch
                            ack_phase <= 1'b0;
                            if (data_reg[7:1] == DEV_ADDR) begin
                                rw_bit <= data_reg[0];
                                if (data_reg[0] == 1'b0) begin
                                    // Write transaction
                                    SDA_oe    <= 1'b0;
                                    state     <= GET_CMD;
                                    bit_count <= 3'd7;
                                    shift_reg <= 8'h00;
                                end else begin
                                    // Read transaction (Fix 6):
                                    // Drive MSB NOW on this falling edge.
                                    // Master will sample it on the 1st SCL rise.
                                    SDA_oe    <= ~tx_data[7];
                                    state     <= SEND_DATA;
                                    bit_count <= 3'd6;  // bit7 already on wire
                                end
                            end else begin
                                SDA_oe <= 1'b0;
                                state  <= IDLE;
                            end
                        end
                    end
                end

                // --------------------------------------------
                // Receive 8-bit command byte
                // --------------------------------------------
                GET_CMD: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda};
                        if (bit_count == 3'd0) begin
                            data_reg  <= {shift_reg[6:0], sda};
                            state     <= CMD_ACK;
                            ack_phase <= 1'b0;
                        end else begin
                            bit_count <= bit_count - 3'd1;
                        end
                    end
                end

                // --------------------------------------------
                // Command ACK (Fix 1 ack_phase pattern)
                // --------------------------------------------
                CMD_ACK: begin
                    if (scl_fall) begin
                        if (!ack_phase) begin
                            SDA_oe    <= 1'b1;
                            ack_phase <= 1'b1;
                        end else begin
                            SDA_oe    <= 1'b0;
                            ack_phase <= 1'b0;
                            cmd_reg   <= data_reg[2:0];
                            state     <= GET_DATA;
                            bit_count <= 3'd7;
                            shift_reg <= 8'h00;
                        end
                    end
                end

                // --------------------------------------------
                // Receive data byte
                // --------------------------------------------
                GET_DATA: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda};
                        if (bit_count == 3'd0) begin
                            data_reg  <= {shift_reg[6:0], sda};
                            state     <= DATA_ACK;
                            ack_phase <= 1'b0;
                        end else begin
                            bit_count <= bit_count - 3'd1;
                        end
                    end
                end

                // --------------------------------------------
                // Data ACK + register write (Fix 1)
                // --------------------------------------------
                DATA_ACK: begin
                    if (scl_fall) begin
                        if (!ack_phase) begin
                            SDA_oe    <= 1'b1;
                            ack_phase <= 1'b1;
                        end else begin
                            SDA_oe    <= 1'b0;
                            ack_phase <= 1'b0;

                            // Write to the addressed register
                            case (cmd_reg)
                                3'd2: output_reg0   <= data_reg;
                                3'd3: output_reg1   <= data_reg;
                                3'd4: polarity_reg0 <= data_reg;
                                3'd5: polarity_reg1 <= data_reg;
                                3'd6: config_reg0   <= data_reg;
                                3'd7: config_reg1   <= data_reg;
                                default: ;           // 0,1 = read-only
                            endcase

                            // Auto-increment register pointer (pair-wise)
                            if (cmd_reg[0] == 1'b1)
                                cmd_reg <= cmd_reg - 3'd1;  // odd  -> even
                            else
                                cmd_reg <= cmd_reg + 3'd1;  // even -> odd

                            state     <= GET_DATA;
                            bit_count <= 3'd7;
                            shift_reg <= 8'h00;
                        end
                    end
                end

                // --------------------------------------------
                // Transmit byte to master, MSB first.
                // Fix 3: drive on scl_fall (data valid before rise).
                // Fix 4: pre-load bit_count=7 on last-bit exit.
                //
                // Entry bit_count values:
                //   First byte after ADDR_ACK  -> bit_count=6
                //     (bit7 was driven in ADDR_ACK, Fix 6)
                //   Subsequent bytes (via READ_ACK) -> bit_count=7
                //     (bit7 driven on ACK-end scl_fall here)
                // --------------------------------------------
                SEND_DATA: begin
                    if (scl_fall) begin
                        SDA_oe <= ~tx_data[bit_count];
                        if (bit_count == 3'd0) begin
                            state     <= READ_ACK;
                            bit_count <= 3'd7;   // Fix 4
                            ack_phase <= 1'b0;   // Fix 7: arm READ_ACK
                        end else begin
                            bit_count <= bit_count - 3'd1;
                        end
                    end
                end

                // --------------------------------------------
                // Wait for master ACK/NACK after transmitted byte.
                //
                // Fix 3: release SDA on scl_fall so master can drive.
                // Fix 7: ack_phase=0 entering; set to 1 on scl_fall.
                //        Only sample ACK/NACK when ack_phase=1.
                //        This skips the scl_rise at the END of the
                //        last data bit (master still reading bit 0)
                //        and only acts on the real ACK clock's rise.
                // Fix 2: refresh input latches on real ACK clock.
                // --------------------------------------------
                READ_ACK: begin
                    if (scl_fall) begin
                        SDA_oe    <= 1'b0;   // Fix 3: release before master drives
                        ack_phase <= 1'b1;   // Fix 7: now armed
                    end
                    if (scl_rise && ack_phase) begin  // Fix 7: only after scl_fall seen
                        // Refresh input latches -> clears int_active (Fix 2)
                        input_latch0 <= port0_in;
                        input_latch1 <= port1_in;
                        ack_phase    <= 1'b0;
                        if (~sda) begin    // ACK -> send next byte
                            if (cmd_reg[0] == 1'b1)
                                cmd_reg <= cmd_reg - 3'd1;
                            else
                                cmd_reg <= cmd_reg + 3'd1;
                            state <= SEND_DATA;
                            // bit_count already 7 from SEND_DATA last-bit path
                        end else begin     // NACK -> done transmitting
                            state <= WAIT_STOP;
                        end
                    end
                end

                // --------------------------------------------
                WAIT_STOP: begin
                    SDA_oe <= 1'b0;
                    if (stop_det) state <= IDLE;
                end

                default: state <= IDLE;

            endcase

            // ------------------------------------------------
            // Global overrides (evaluated AFTER case block so
            // they always take priority).
            //
            // STOP  : return to IDLE from any state.
            // Fix 5 (repeated-START): start_det from any non-IDLE
            //   state jumps to GET_ADDR, preserving cmd_reg.
            // ------------------------------------------------
            if (stop_det) begin
                state     <= IDLE;
                SDA_oe    <= 1'b0;
                ack_phase <= 1'b0;
            end else if (start_det && (state != IDLE)) begin
                // Repeated START mid-transaction (Fix 5)
                state     <= GET_ADDR;
                bit_count <= 3'd7;
                shift_reg <= 8'h00;
                SDA_oe    <= 1'b0;
                ack_phase <= 1'b0;
                // cmd_reg intentionally NOT cleared
            end
        end
    end
endmodule
