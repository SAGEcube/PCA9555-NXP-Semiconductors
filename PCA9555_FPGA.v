`timescale 1ns/1ps

    module pca9555_single (
        input  wire clk,
        input  wire rst,
        input  wire SCL,
        input  wire SDA_in,
        output reg  SDA_oe,
        output wire int_active,

        output wire [7:0] port0_out,
        input  wire [7:0] port0_in
    );
    // Address pins fixed to 0 (GND)
// Address pins fixed to 0 (GND)
wire A0 = 1'b0;
wire A1 = 1'b0;
wire A2 = 1'b0;
wire [7:0] port0_oe  = ~config_reg0;

    reg [7:0] config_reg0;
    reg [7:0] output_reg0;
    reg [7:0] polarity_reg0;
    reg [7:0] input_latch0;

    assign port0_oe  = ~config_reg0;
    assign port0_out = output_reg0;

    wire [7:0] input_reg0 = port0_in ^ polarity_reg0;

    assign int_active = |((port0_in ^ input_latch0) & config_reg0);

    // ================= FSM =================

    reg [3:0] state;
    reg [2:0] bit_count;
    reg [7:0] shift_reg;
    reg [7:0] data_reg;
    reg [2:0] cmd_reg;
    reg ack_phase;

    localparam IDLE=0, GET_ADDR=1, ADDR_ACK=2, GET_CMD=3,
               CMD_ACK=4, GET_DATA=5, DATA_ACK=6,
               SEND_DATA=7, READ_ACK=8;

    wire DEV_MATCH = (shift_reg[7:1] == 7'b0100000);

    reg scl_d, scl_dd, sda_d, sda_dd;

    always @(posedge clk) begin
        scl_d <= SCL; scl_dd <= scl_d;
        sda_d <= SDA_in; sda_dd <= sda_d;
    end

    wire scl_rise = (scl_d && !scl_dd);
    wire scl_fall = (!scl_d && scl_dd);

    reg [7:0] tx_data;

    always @(*) begin
        case(cmd_reg)
            3'd0: tx_data = input_reg0;
            3'd2: tx_data = output_reg0;
            3'd4: tx_data = polarity_reg0;
            3'd6: tx_data = config_reg0;
            default: tx_data = 8'h00;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            config_reg0 <= 8'hFF;
            output_reg0 <= 8'hFF;
            polarity_reg0 <= 8'h00;
            input_latch0 <= 8'hFF;
            SDA_oe <= 0;
            bit_count <= 7;
        end else begin
            case(state)

            IDLE: begin
                SDA_oe <= 0;
                if (!sda_d && sda_dd) state <= GET_ADDR;
            end

            GET_ADDR: if (scl_rise) begin
                shift_reg <= {shift_reg[6:0], sda_dd};
                if (bit_count==0) state<=ADDR_ACK;
                else bit_count<=bit_count-1;
            end

            ADDR_ACK: begin
                SDA_oe <= 1;
                if (DEV_MATCH) state<=GET_CMD;
                else state<=IDLE;
                bit_count<=7;
            end

            GET_CMD: if (scl_rise) begin
                shift_reg <= {shift_reg[6:0], sda_dd};
                if (bit_count==0) begin
                    cmd_reg<=shift_reg[2:0];
                    state<=CMD_ACK;
                end else bit_count<=bit_count-1;
            end

            CMD_ACK: begin
                SDA_oe<=1;
                state<=GET_DATA;
                bit_count<=7;
            end

            GET_DATA: if (scl_rise) begin
                shift_reg <= {shift_reg[6:0], sda_dd};
                if (bit_count==0) begin
                    data_reg<=shift_reg;
                    state<=DATA_ACK;
                end else bit_count<=bit_count-1;
            end

            DATA_ACK: begin
                SDA_oe<=1;
                case(cmd_reg)
                    3'd2: output_reg0<=data_reg;
                    3'd4: polarity_reg0<=data_reg;
                    3'd6: config_reg0<=data_reg;
                endcase
                state<=IDLE;
            end

            default: state<=IDLE;

            endcase
        end
    end

    endmodule

    `timescale 1ns/1ps

    module pca9555_single (
        input  wire clk,
        input  wire rst,
        input  wire SCL,
        input  wire SDA_in,
        output reg  SDA_oe,
        output wire int_active,

        output wire [7:0] port0_out,
        input  wire [7:0] port0_in
    );
    // Address pins fixed to 0 (GND)
// Address pins fixed to 0 (GND)
wire A0 = 1'b0;
wire A1 = 1'b0;
wire A2 = 1'b0;
wire [7:0] port0_oe  = ~config_reg0;

    reg [7:0] config_reg0;
    reg [7:0] output_reg0;
    reg [7:0] polarity_reg0;
    reg [7:0] input_latch0;

    assign port0_oe  = ~config_reg0;
    assign port0_out = output_reg0;

    wire [7:0] input_reg0 = port0_in ^ polarity_reg0;

    assign int_active = |((port0_in ^ input_latch0) & config_reg0);

    // ================= FSM =================

    reg [3:0] state;
    reg [2:0] bit_count;
    reg [7:0] shift_reg;
    reg [7:0] data_reg;
    reg [2:0] cmd_reg;
    reg ack_phase;

    localparam IDLE=0, GET_ADDR=1, ADDR_ACK=2, GET_CMD=3,
               CMD_ACK=4, GET_DATA=5, DATA_ACK=6,
               SEND_DATA=7, READ_ACK=8;

    wire DEV_MATCH = (shift_reg[7:1] == 7'b0100000);

    reg scl_d, scl_dd, sda_d, sda_dd;

    always @(posedge clk) begin
        scl_d <= SCL; scl_dd <= scl_d;
        sda_d <= SDA_in; sda_dd <= sda_d;
    end

    wire scl_rise = (scl_d && !scl_dd);
    wire scl_fall = (!scl_d && scl_dd);

    reg [7:0] tx_data;

    always @(*) begin
        case(cmd_reg)
            3'd0: tx_data = input_reg0;
            3'd2: tx_data = output_reg0;
            3'd4: tx_data = polarity_reg0;
            3'd6: tx_data = config_reg0;
            default: tx_data = 8'h00;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            config_reg0 <= 8'hFF;
            output_reg0 <= 8'hFF;
            polarity_reg0 <= 8'h00;
            input_latch0 <= 8'hFF;
            SDA_oe <= 0;
            bit_count <= 7;
        end else begin
            case(state)

            IDLE: begin
                SDA_oe <= 0;
                if (!sda_d && sda_dd) state <= GET_ADDR;
            end

            GET_ADDR: if (scl_rise) begin
                shift_reg <= {shift_reg[6:0], sda_dd};
                if (bit_count==0) state<=ADDR_ACK;
                else bit_count<=bit_count-1;
            end

            ADDR_ACK: begin
                SDA_oe <= 1;
                if (DEV_MATCH) state<=GET_CMD;
                else state<=IDLE;
                bit_count<=7;
            end

            GET_CMD: if (scl_rise) begin
                shift_reg <= {shift_reg[6:0], sda_dd};
                if (bit_count==0) begin
                    cmd_reg<=shift_reg[2:0];
                    state<=CMD_ACK;
                end else bit_count<=bit_count-1;
            end

            CMD_ACK: begin
                SDA_oe<=1;
                state<=GET_DATA;
                bit_count<=7;
            end

            GET_DATA: if (scl_rise) begin
                shift_reg <= {shift_reg[6:0], sda_dd};
                if (bit_count==0) begin
                    data_reg<=shift_reg;
                    state<=DATA_ACK;
                end else bit_count<=bit_count-1;
            end

            DATA_ACK: begin
                SDA_oe<=1;
                case(cmd_reg)
                    3'd2: output_reg0<=data_reg;
                    3'd4: polarity_reg0<=data_reg;
                    3'd6: config_reg0<=data_reg;
                endcase
                state<=IDLE;
            end

            default: state<=IDLE;

            endcase
        end
    end