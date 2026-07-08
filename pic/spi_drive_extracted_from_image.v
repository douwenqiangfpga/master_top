/*
主从FPGA通信spi驱动数据收发模块
        2025.8.28 创建文件
*/
`include "define.v"

module SPI_DRIVE(
    input              clk_160M,
    input              clk_100M,
    input              rst_n,

    //spi输出slave信号
    output reg         o_spi_sclk/*synthesis PAP_MARK_DEBUG = "1"*/,
    output reg         o_spi_cs/*synthesis PAP_MARK_DEBUG = "1"*/,
    output reg         o_spi_mosi,/*synthesis PAP_MARK_DEBUG = "1"*/

    //spi发送slave数据
    input      [47:0]  i_spi_tx_data,
    input              i_spi_tx_st,/*synthesis PAP_MARK_DEBUG = "1"*/
    input      [15:0]  i_spi_rx_bit_wide,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire        o_spi_tx_done,

    //spi输入slave信号
    input              i_spi_miso1,
    input              i_spi_miso2,
    input              i_spi_miso3,
    input              i_spi_miso4,

    //spi_rx_data
    output wire [367:0] o_spi_rx_data1/*synthesis PAP_MARK_DEBUG = "1"*/,
    output wire [367:0] o_spi_rx_data2,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire [376:0] o_spi_rx_data3,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire [376:0] o_spi_rx_data4,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire         o_spi_rx_done,

    output wire [3:0]   o_spi_state
);

localparam      SPI_TX_BIT_WIDTH = 'd48;

localparam      SPI_TX_CNT_MAX = SPI_TX_BIT_WIDTH - 1;  /*synthesis PAP_MARK_DEBUG = "1"*/

reg     [15:0]  r_spi_tx_bit_cnt='b0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [15:0]  r_spi_rx_bit_cnt='b0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [47:0]  r_spi_tx_reg;/*synthesis PAP_MARK_DEBUG = "1"*/

reg     [367:0] r_spi_rx_data1;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [367:0] r_spi_rx_data2;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [367:0] r_spi_rx_data3;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [367:0] r_spi_rx_data4;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_rx_done;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_tx_st_r0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_tx_cnt_done='b0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_rx_cnt_done='b0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_cs_d0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_sclk_d0;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_rx_cnt_done1;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [15:0]  r_spi_rx_bit_wide_d0;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_rx_done_d0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_rx_done_d1;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_rx_done_d2;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [47:0]  r_spi_tx_data;

always @(posedge clk_160M)begin
    r_spi_tx_st_r0 <= i_spi_tx_st;
    r_spi_cs_d0    <= o_spi_cs;
    r_spi_tx_data  <= i_spi_tx_data;
end

//r_spi_tx_reg
always @(posedge clk_160M)begin
    if(r_spi_tx_st_r0)
        r_spi_tx_reg <= r_spi_tx_data;
    else
        r_spi_tx_reg <= r_spi_tx_reg;
end

//o_spi_cs
always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)
        o_spi_cs <= 'd1;
    else if(r_spi_tx_st_r0)
        o_spi_cs <= 'd0;
    else if(r_spi_rx_cnt_done1)
        o_spi_cs <= 'd1;
    else
        o_spi_cs <= o_spi_cs;
end

//o_spi_sclk
reg     [1:0]   clk_cnt;
always @(posedge clk_160M)begin
    if(r_spi_cs_d0)begin
        o_spi_sclk <= 1'b1;
        clk_cnt    <= 1'b0;
    end
    else if(~r_spi_cs_d0) begin
        if(clk_cnt=='b1)begin
            o_spi_sclk <= ~o_spi_sclk;
            clk_cnt    <= 'b0;
        end
        else begin
            o_spi_sclk <= o_spi_sclk;
            clk_cnt    <= clk_cnt + 'b1;
        end
    end
end

//r_spi_rx_cnt_done1
always @(posedge clk_160M)begin
    r_spi_rx_cnt_done1 <= r_spi_rx_cnt_done;
end

//r_spi_rx_bit_wide_d0
always @(posedge o_spi_sclk)begin
    r_spi_rx_bit_wide_d0 <= i_spi_rx_bit_wide;
end

//
always @(posedge o_spi_sclk or posedge r_spi_cs_d0)begin
    if(r_spi_cs_d0)begin
        r_spi_tx_bit_cnt  <= 'd0;
        r_spi_tx_cnt_done <= 'd0;
    end
    else if(r_spi_tx_bit_cnt == SPI_TX_BIT_WIDTH)begin
        r_spi_tx_bit_cnt  <= 'd0;
        r_spi_tx_cnt_done <= 'd1;
        o_spi_mosi        <= 'd0;
    end
    else if(!r_spi_tx_cnt_done) begin//SPI发送
        r_spi_tx_bit_cnt <= r_spi_tx_bit_cnt + 'd1;
        o_spi_mosi       <= r_spi_tx_reg[SPI_TX_CNT_MAX-r_spi_tx_bit_cnt];
    end
end

//r_spi_rx_data
always @(negedge o_spi_sclk or posedge r_spi_cs_d0)begin
    if(r_spi_cs_d0)begin
        r_spi_rx_bit_cnt  <= 'd0;
        r_spi_rx_cnt_done <= 'd0;
        r_spi_rx_done     <= 'd0;
        r_spi_rx_data1    <= 'd0;
        r_spi_rx_data2    <= 'd0;
        r_spi_rx_data3    <= 'd0;
        r_spi_rx_data4    <= 'd0;
    end
    else if(r_spi_rx_bit_cnt == r_spi_rx_bit_wide_d0 - 1)begin
        r_spi_rx_bit_cnt  <= 'd0;
        r_spi_rx_cnt_done <= 'd1;
        r_spi_rx_done     <= 'd1;
    end
    else if(~r_spi_rx_cnt_done&&r_spi_tx_cnt_done)begin
        if(r_spi_rx_bit_cnt >= 'd25)begin
            if(r_spi_rx_bit_wide_d0 == ('d48+'d26))begin
                r_spi_rx_data1 <= {r_spi_rx_data1[46:0], i_spi_miso1};
                r_spi_rx_data2 <= {r_spi_rx_data2[46:0], i_spi_miso2};
                r_spi_rx_data3 <= {r_spi_rx_data3[46:0], i_spi_miso3};
                r_spi_rx_data4 <= {r_spi_rx_data4[46:0], i_spi_miso4};
            end
            else if(r_spi_rx_bit_wide_d0 == ('d160+'d26))begin
                r_spi_rx_data1 <= {r_spi_rx_data1[158:0], i_spi_miso1};
                r_spi_rx_data2 <= {r_spi_rx_data2[158:0], i_spi_miso2};
                r_spi_rx_data3 <= {r_spi_rx_data3[158:0], i_spi_miso3};
                r_spi_rx_data4 <= {r_spi_rx_data4[158:0], i_spi_miso4};
            end
            else if(r_spi_rx_bit_wide_d0 == ('d368+'d26))begin
                r_spi_rx_data1 <= {r_spi_rx_data1[366:0], i_spi_miso1};
                r_spi_rx_data2 <= {r_spi_rx_data2[366:0], i_spi_miso2};
                r_spi_rx_data3 <= {r_spi_rx_data3[366:0], i_spi_miso3};
                r_spi_rx_data4 <= {r_spi_rx_data4[366:0], i_spi_miso4};
            end
        end

        r_spi_rx_bit_cnt <= r_spi_rx_bit_cnt + 'd1;
    end
end

always @(posedge clk_100M)begin
    r_spi_rx_done_d0 <= r_spi_rx_done;
    r_spi_rx_done_d1 <= r_spi_rx_done_d0;
    r_spi_rx_done_d2 <= r_spi_rx_done_d1;
end

assign  o_spi_rx_done = r_spi_rx_done_d2;

SPI_FIFO_MISO1 SPI_FIFO1_INST(
    .wr_clk(o_spi_sclk),              // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data1),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(r_spi_rx_done_d0),         // input
    .rd_data(o_spi_rx_data1),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

SPI_FIFO_MISO2 SPI_FIFO2_INST (
    .wr_clk(o_spi_sclk),              // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data2),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(r_spi_rx_done_d0),         // input
    .rd_data(o_spi_rx_data2),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

SPI_FIFO_MISO3 SPI_FIFO3_INST (
    .wr_clk(o_spi_sclk),              // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data3),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(r_spi_rx_done_d0),         // input
    .rd_data(o_spi_rx_data3),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

SPI_FIFO_MISO4 SPI_FIFO4_INST (
    .wr_clk(o_spi_sclk),              // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data4),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(r_spi_rx_done_d0),         // input
    .rd_data(o_spi_rx_data4),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

endmodule
