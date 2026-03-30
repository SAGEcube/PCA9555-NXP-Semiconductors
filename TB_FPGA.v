`timescale 1ns/1ps

module tb;

reg clk=0, rst=1;
reg SCL=1;
reg SDA_tb=0;
wire SDA_oe;

wire SDA = (SDA_tb | SDA_oe) ? 0 : 1;

wire [7:0] port0_oe, port0_out, port0_in;
reg  [7:0] port0_ext;

assign port0_in = port0_oe ? port0_out : port0_ext;

pca9555_single DUT (
    .clk(clk),
    .rst(rst),
    .SCL(SCL),
    .SDA_in(SDA),
    .SDA_oe(SDA_oe),
    .A0(0), .A1(0), .A2(0),
    .int_active(),
    .port0_oe(port0_oe),
    .port0_out(port0_out),
    .port0_in(port0_in)
);

always #50 clk = ~clk;

initial begin
    port0_ext = 8'hFF;
    #100 rst = 0;

    #500 port0_ext = 8'hAA;
    #1000 port0_ext = 8'h55;

    #5000 $finish;
end

endmodule