`timescale 1ns/1ps

// Standalone timing testbench for rtl/SPI_DRIVE.v.
//
// Compile from project root, for example:
//   vlog +incdir+rtl sim/tb_spi_drive.v rtl/SPI_DRIVE.v
//   vsim -voptargs=+acc work.tb_spi_drive
//   run 30 us
//
// The slave model samples MOSI on SCLK rising edge and updates MISO on SCLK
// rising edge, so the master should sample MISO on the following falling edge.

module tb_spi_drive;

localparam [47:0] TX_WORD       = 48'hF102_0002_0000;
localparam [47:0] MISO1_WORD    = 48'h0F01_0002_0000;
localparam [47:0] MISO2_WORD    = 48'h1234_5678_9ABC;
localparam [47:0] MISO3_WORD    = 48'h55AA_A55A_0FF0;
localparam [47:0] MISO4_WORD    = 48'hA5C3_5AA5_F00F;
localparam [15:0] RX_BIT_WIDTH  = 16'd74;
localparam integer TX_BITS      = 48;
localparam integer MISO_SKIP    = 16;

reg             clk_160M;
reg             clk_100M;
reg             rst_n;
reg     [47:0]  i_spi_tx_data;
reg             i_spi_tx_st;
reg     [15:0]  i_spi_rx_bit_wide;
wire            o_spi_tx_done;
reg             i_spi_miso1;
reg             i_spi_miso2;
reg             i_spi_miso3;
reg             i_spi_miso4;
wire            o_spi_sclk;
wire            o_spi_cs;
wire            o_spi_mosi;
wire    [367:0] o_spi_rx_data1;
wire    [367:0] o_spi_rx_data2;
wire    [367:0] o_spi_rx_data3;
wire    [367:0] o_spi_rx_data4;
wire            o_spi_rx_done;
wire    [3:0]   o_spi_state;

reg     [47:0]  slave_rx_shift;
reg     [47:0]  slave_rx_last;
integer         slave_rx_cnt;
integer         slave_rx_last_cnt;
integer         miso_delay_cnt;
integer         miso_bit_cnt;

SPI_DRIVE dut (
    .clk_160M          (clk_160M),
    .clk_100M          (clk_100M),
    .rst_n             (rst_n),
    .o_spi_sclk        (o_spi_sclk),
    .o_spi_cs          (o_spi_cs),
    .o_spi_mosi        (o_spi_mosi),
    .i_spi_tx_data     (i_spi_tx_data),
    .i_spi_tx_st       (i_spi_tx_st),
    .i_spi_rx_bit_wide (i_spi_rx_bit_wide),
    .o_spi_tx_done     (o_spi_tx_done),
    .i_spi_miso1       (i_spi_miso1),
    .i_spi_miso2       (i_spi_miso2),
    .i_spi_miso3       (i_spi_miso3),
    .i_spi_miso4       (i_spi_miso4),
    .o_spi_rx_data1    (o_spi_rx_data1),
    .o_spi_rx_data2    (o_spi_rx_data2),
    .o_spi_rx_data3    (o_spi_rx_data3),
    .o_spi_rx_data4    (o_spi_rx_data4),
    .o_spi_rx_done     (o_spi_rx_done),
    .o_spi_state       (o_spi_state)
);

initial begin
    clk_160M = 1'b0;
    forever #3.125 clk_160M = ~clk_160M;
end

initial begin
    clk_100M = 1'b0;
    forever #5 clk_100M = ~clk_100M;
end

initial begin
    $dumpfile("tb_spi_drive.vcd");
    $dumpvars(0, tb_spi_drive);
end

initial begin
    rst_n             = 1'b0;
    i_spi_tx_data     = 48'd0;
    i_spi_tx_st       = 1'b0;
    i_spi_rx_bit_wide = 16'd0;
    i_spi_miso1       = 1'b0;
    i_spi_miso2       = 1'b0;
    i_spi_miso3       = 1'b0;
    i_spi_miso4       = 1'b0;
    slave_rx_shift    = 48'd0;
    slave_rx_last     = 48'd0;
    slave_rx_cnt      = 0;
    slave_rx_last_cnt = 0;

    #100;
    rst_n = 1'b1;
    repeat (10) @(posedge clk_100M);

    start_spi_transfer(TX_WORD, RX_BIT_WIDTH);

    wait (o_spi_rx_done == 1'b1);
    #1;
    $display("[%0t] slave sampled MOSI = 0x%012h, cnt=%0d", $time, slave_rx_last, slave_rx_last_cnt);
    $display("[%0t] master rx1[47:0]   = 0x%012h", $time, o_spi_rx_data1[47:0]);
    $display("[%0t] master rx2[47:0]   = 0x%012h", $time, o_spi_rx_data2[47:0]);
    $display("[%0t] master rx3[47:0]   = 0x%012h", $time, o_spi_rx_data3[47:0]);
    $display("[%0t] master rx4[47:0]   = 0x%012h", $time, o_spi_rx_data4[47:0]);

    if (slave_rx_last !== TX_WORD)
        $display("ERROR: MOSI word mismatch, expected 0x%012h", TX_WORD);
    if (o_spi_rx_data1[47:0] !== MISO1_WORD)
        $display("ERROR: MISO1 word mismatch, expected 0x%012h", MISO1_WORD);

    repeat (20) @(posedge clk_100M);
    $finish;
end

initial begin
    #30000;
    $display("ERROR: simulation timeout. Check r_spi_tx_bit_cnt, r_spi_tx_cnt_done, and o_spi_cs.");
    $finish;
end

task start_spi_transfer;
    input [47:0] tx_data;
    input [15:0] rx_bit_width;
    begin
        @(posedge clk_100M);
        i_spi_tx_data     = tx_data;
        i_spi_rx_bit_wide = rx_bit_width;
        i_spi_tx_st       = 1'b1;
        @(posedge clk_100M);
        i_spi_tx_st       = 1'b0;
    end
endtask

always @(negedge o_spi_cs) begin
    slave_rx_shift <= 48'd0;
    slave_rx_cnt   <= 0;
end

always @(posedge o_spi_cs) begin
    slave_rx_last     <= slave_rx_shift;
    slave_rx_last_cnt <= slave_rx_cnt;
end

// Slave-side MOSI monitor: current slave COM_RECEIVE samples MOSI on SCLK rise.
always @(posedge o_spi_sclk) begin
    if (!o_spi_cs && (slave_rx_cnt < TX_BITS)) begin
        slave_rx_shift <= {slave_rx_shift[46:0], o_spi_mosi};
        slave_rx_cnt   <= slave_rx_cnt + 1;
    end
end

// Slave-side MISO model: current slave COM_SEND changes MISO on SCLK rise.
// The master should capture these bits on the following SCLK falling edge.
always @(posedge o_spi_sclk or posedge o_spi_cs) begin
    if (o_spi_cs) begin
        i_spi_miso1    <= 1'b0;
        i_spi_miso2    <= 1'b0;
        i_spi_miso3    <= 1'b0;
        i_spi_miso4    <= 1'b0;
        miso_delay_cnt <= 0;
        miso_bit_cnt   <= 0;
    end
    else if (dut.r_spi_tx_cnt_done) begin
        if (miso_delay_cnt < MISO_SKIP) begin
            miso_delay_cnt <= miso_delay_cnt + 1;
            i_spi_miso1    <= 1'b0;
            i_spi_miso2    <= 1'b0;
            i_spi_miso3    <= 1'b0;
            i_spi_miso4    <= 1'b0;
        end
        else if (miso_bit_cnt < TX_BITS) begin
            i_spi_miso1  <= MISO1_WORD[TX_BITS-1-miso_bit_cnt];
            i_spi_miso2  <= MISO2_WORD[TX_BITS-1-miso_bit_cnt];
            i_spi_miso3  <= MISO3_WORD[TX_BITS-1-miso_bit_cnt];
            i_spi_miso4  <= MISO4_WORD[TX_BITS-1-miso_bit_cnt];
            miso_bit_cnt <= miso_bit_cnt + 1;
        end
        else begin
            i_spi_miso1 <= 1'b0;
            i_spi_miso2 <= 1'b0;
            i_spi_miso3 <= 1'b0;
            i_spi_miso4 <= 1'b0;
        end
    end
end

endmodule

module tb_spi_fifo_stub (
    input              wr_clk,
    input              wr_rst,
    input              wr_en,
    input      [367:0] wr_data,
    output             wr_full,
    output             almost_full,
    input              rd_clk,
    input              rd_rst,
    input              rd_en,
    output reg [367:0] rd_data,
    output             rd_empty,
    output             almost_empty
);
reg [367:0] mem;

assign wr_full      = 1'b0;
assign almost_full  = 1'b0;
assign rd_empty     = 1'b0;
assign almost_empty = 1'b0;

always @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst)
        mem <= 368'd0;
    else if (wr_en)
        mem <= wr_data;
end

always @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst)
        rd_data <= 368'd0;
    else if (rd_en)
        rd_data <= mem;
end

endmodule

module SPI_FIFO_MISO1 (
    input wr_clk,
    input wr_rst,
    input wr_en,
    input [367:0] wr_data,
    output wr_full,
    output almost_full,
    input rd_clk,
    input rd_rst,
    input rd_en,
    output [367:0] rd_data,
    output rd_empty,
    output almost_empty
);
tb_spi_fifo_stub u_fifo (
    .wr_clk(wr_clk),
    .wr_rst(wr_rst),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .wr_full(wr_full),
    .almost_full(almost_full),
    .rd_clk(rd_clk),
    .rd_rst(rd_rst),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .rd_empty(rd_empty),
    .almost_empty(almost_empty)
);
endmodule

module SPI_FIFO_MISO2 (
    input wr_clk,
    input wr_rst,
    input wr_en,
    input [367:0] wr_data,
    output wr_full,
    output almost_full,
    input rd_clk,
    input rd_rst,
    input rd_en,
    output [367:0] rd_data,
    output rd_empty,
    output almost_empty
);
tb_spi_fifo_stub u_fifo (
    .wr_clk(wr_clk),
    .wr_rst(wr_rst),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .wr_full(wr_full),
    .almost_full(almost_full),
    .rd_clk(rd_clk),
    .rd_rst(rd_rst),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .rd_empty(rd_empty),
    .almost_empty(almost_empty)
);
endmodule

module SPI_FIFO_MISO3 (
    input wr_clk,
    input wr_rst,
    input wr_en,
    input [367:0] wr_data,
    output wr_full,
    output almost_full,
    input rd_clk,
    input rd_rst,
    input rd_en,
    output [367:0] rd_data,
    output rd_empty,
    output almost_empty
);
tb_spi_fifo_stub u_fifo (
    .wr_clk(wr_clk),
    .wr_rst(wr_rst),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .wr_full(wr_full),
    .almost_full(almost_full),
    .rd_clk(rd_clk),
    .rd_rst(rd_rst),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .rd_empty(rd_empty),
    .almost_empty(almost_empty)
);
endmodule

module SPI_FIFO_MISO4 (
    input wr_clk,
    input wr_rst,
    input wr_en,
    input [367:0] wr_data,
    output wr_full,
    output almost_full,
    input rd_clk,
    input rd_rst,
    input rd_en,
    output [367:0] rd_data,
    output rd_empty,
    output almost_empty
);
tb_spi_fifo_stub u_fifo (
    .wr_clk(wr_clk),
    .wr_rst(wr_rst),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .wr_full(wr_full),
    .almost_full(almost_full),
    .rd_clk(rd_clk),
    .rd_rst(rd_rst),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .rd_empty(rd_empty),
    .almost_empty(almost_empty)
);
endmodule
