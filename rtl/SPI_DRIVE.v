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
    output reg         o_spi_mosi/*synthesis PAP_MARK_DEBUG = "1"*/,

    //spi发送slave数据
    input      [47:0]  i_spi_tx_data/*synthesis PAP_MARK_DEBUG = "1"*/,
    input              i_spi_tx_st/*synthesis PAP_MARK_DEBUG = "1"*/,
    input      [15:0]  i_spi_rx_bit_wide/*synthesis PAP_MARK_DEBUG = "1"*/,
    output wire        o_spi_tx_done,

    //spi输入slave信号
    input              i_spi_miso1/*synthesis PAP_MARK_DEBUG = "1"*/,
    input              i_spi_miso2/*synthesis PAP_MARK_DEBUG = "1"*/,
    input              i_spi_miso3/*synthesis PAP_MARK_DEBUG = "1"*/,
    input              i_spi_miso4/*synthesis PAP_MARK_DEBUG = "1"*/,

    //spi_rx_data
    output wire [367:0] o_spi_rx_data1/*synthesis PAP_MARK_DEBUG = "1"*/,
    output wire [367:0] o_spi_rx_data2,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire [367:0] o_spi_rx_data3,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire [367:0] o_spi_rx_data4,/*synthesis PAP_MARK_DEBUG = "1"*/
    output wire         o_spi_rx_done,

    output wire [3:0]   o_spi_state
);

localparam      SPI_TX_BIT_WIDTH = 'd48;

localparam      SPI_TX_CNT_MAX = SPI_TX_BIT_WIDTH - 1;  /*synthesis PAP_MARK_DEBUG = "1"*/
localparam      SPI_RX_SKIP_CNT = 16'd26;
localparam      SPI_RX_CAP_FIRST = 16'd16;
localparam      SPI_SCLK_HALF_CYC = 4'd8;   // 160MHz / (2 * 8) = 10MHz
localparam      SPI_SCLK_TOGGLE_CNT = SPI_SCLK_HALF_CYC - 4'd1;

reg     [15:0]  r_spi_tx_bit_cnt='b0/*synthesis PAP_MARK_DEBUG = "1"*/;
reg     [15:0]  r_spi_rx_bit_cnt='b0/*synthesis PAP_MARK_DEBUG = "1"*/;
reg     [47:0]  r_spi_tx_reg/*synthesis PAP_MARK_DEBUG = "1"*/;

reg     [367:0] r_spi_rx_data1;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [367:0] r_spi_rx_data2;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [367:0] r_spi_rx_data3;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [367:0] r_spi_rx_data4;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_rx_done;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_tx_st_r0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_tx_st_meta;
reg             r_spi_tx_st_sync;
reg             r_spi_tx_st_sync_d;
reg             r_spi_tx_cnt_done='b0/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             r_spi_rx_cnt_done='b0/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             r_spi_cs_d0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_sclk_d0;/*synthesis PAP_MARK_DEBUG = "1"*/

reg             r_spi_rx_cnt_done1;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [15:0]  r_spi_rx_bit_wide_d0 /*synthesis PAP_MARK_DEBUG = "1"*/;

reg             r_spi_rx_done_d0;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_rx_done_d1;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_rx_done_d2;/*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_spi_rx_done_d3;/*synthesis PAP_MARK_DEBUG = "1"*/
reg     [47:0]  r_spi_tx_data/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             r_spi_fifo_rd_en;
reg             r_spi_fifo_data_valid;
wire            w_spi_fifo_rd_pulse;
wire            w_spi_rx_done_pulse;
wire            w_spi_tx_st_160m/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            w_spi_tx_accept/*synthesis PAP_MARK_DEBUG = "1"*/;
wire    [15:0]  w_spi_rx_cap_first;
wire    [15:0]  w_spi_rx_cap_last;
wire    [15:0]  w_spi_rx_done_last;
wire    [15:0]  w_spi_rx_data_bits;

assign  w_spi_tx_st_160m = r_spi_tx_st_sync & ~r_spi_tx_st_sync_d;
assign  w_spi_tx_accept  = w_spi_tx_st_160m && o_spi_cs && !r_spi_tx_st_r0;
assign  w_spi_rx_cap_first = SPI_RX_CAP_FIRST;
assign  w_spi_rx_data_bits = r_spi_rx_bit_wide_d0 - SPI_RX_SKIP_CNT;
assign  w_spi_rx_cap_last  = w_spi_rx_cap_first + w_spi_rx_data_bits - 16'd1;
assign  w_spi_rx_done_last = r_spi_rx_bit_wide_d0 - 16'd2;

always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)begin
        r_spi_tx_st_meta   <= 1'b0;
        r_spi_tx_st_sync   <= 1'b0;
        r_spi_tx_st_sync_d <= 1'b0;
        r_spi_tx_st_r0     <= 1'b0;
        r_spi_cs_d0        <= 1'b1;
        r_spi_tx_data      <= 48'd0;
    end
    else begin
        r_spi_tx_st_meta   <= i_spi_tx_st;
        r_spi_tx_st_sync   <= r_spi_tx_st_meta;
        r_spi_tx_st_sync_d <= r_spi_tx_st_sync;
        r_spi_tx_st_r0     <= w_spi_tx_accept;
        r_spi_cs_d0        <= o_spi_cs;
        if(w_spi_tx_accept)
            r_spi_tx_data <= i_spi_tx_data;
    end
end

//r_spi_tx_reg
always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)
        r_spi_tx_reg <= 48'd0;
    else if(r_spi_tx_st_r0)
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
reg     [3:0]   clk_cnt;
wire            spi_sclk_toggle;
wire            spi_sclk_pos/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            spi_sclk_neg/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             spi_sclk_neg_d;

assign spi_sclk_toggle = (~o_spi_cs) && (~r_spi_cs_d0) && (clk_cnt == SPI_SCLK_TOGGLE_CNT);
assign spi_sclk_pos    = spi_sclk_toggle && (o_spi_sclk == 1'b0);
assign spi_sclk_neg    = spi_sclk_toggle && (o_spi_sclk == 1'b1);

always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)begin
        o_spi_sclk   <= 1'b1;
        clk_cnt      <= 4'd0;
        spi_sclk_neg_d <= 1'b0;
    end
    else begin
        spi_sclk_neg_d <= spi_sclk_neg;

        if(o_spi_cs)begin
            o_spi_sclk <= 1'b1;
            clk_cnt    <= 4'd0;
        end
        else if(r_spi_cs_d0)begin
            o_spi_sclk <= 1'b0;
            clk_cnt    <= 4'd0;
        end
        else if(clk_cnt == SPI_SCLK_TOGGLE_CNT)begin
            o_spi_sclk   <= ~o_spi_sclk;
            clk_cnt      <= 4'd0;
        end
        else begin
            clk_cnt <= clk_cnt + 4'd1;
        end
    end
end

//r_spi_rx_cnt_done1
always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)
        r_spi_rx_cnt_done1 <= 1'b0;
    else
        r_spi_rx_cnt_done1 <= r_spi_rx_cnt_done;
end

//r_spi_rx_bit_wide_d0
always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)
        r_spi_rx_bit_wide_d0 <= 16'd0;
    else if(w_spi_tx_accept)
        r_spi_rx_bit_wide_d0 <= i_spi_rx_bit_wide;
end

//
always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)begin
        r_spi_tx_bit_cnt  <= 16'd0;
        r_spi_tx_cnt_done <= 1'b0;
        o_spi_mosi        <= 1'b0;
    end
    else if(r_spi_cs_d0)begin
        r_spi_tx_bit_cnt  <= 'd0;
        r_spi_tx_cnt_done <= 'd0;
        o_spi_mosi        <= 1'b0;
    end
    else if(!r_spi_tx_cnt_done && (r_spi_tx_bit_cnt == 16'd0))begin
        r_spi_tx_bit_cnt <= 16'd1;
        o_spi_mosi       <= r_spi_tx_reg[SPI_TX_CNT_MAX];
    end
    else if(spi_sclk_neg)begin
        if(r_spi_tx_bit_cnt == SPI_TX_BIT_WIDTH)begin
            r_spi_tx_bit_cnt  <= 'd0;
            r_spi_tx_cnt_done <= 'd1;
            o_spi_mosi        <= 'd0;
        end
        else if(!r_spi_tx_cnt_done) begin//SPI发送
            r_spi_tx_bit_cnt <= r_spi_tx_bit_cnt + 'd1;
            o_spi_mosi       <= r_spi_tx_reg[SPI_TX_CNT_MAX-r_spi_tx_bit_cnt];
        end
    end
end

//r_spi_rx_data
always @(posedge clk_160M or negedge rst_n)begin
    if(!rst_n)begin
        r_spi_rx_bit_cnt  <= 16'd0;
        r_spi_rx_cnt_done <= 1'b0;
        r_spi_rx_done     <= 1'b0;
        r_spi_rx_data1    <= 368'd0;
        r_spi_rx_data2    <= 368'd0;
        r_spi_rx_data3    <= 368'd0;
        r_spi_rx_data4    <= 368'd0;
    end
    else if(r_spi_cs_d0)begin
        r_spi_rx_bit_cnt  <= 'd0;
        r_spi_rx_cnt_done <= 'd0;
        r_spi_rx_done     <= 'd0;
        r_spi_rx_data1    <= 'd0;
        r_spi_rx_data2    <= 'd0;
        r_spi_rx_data3    <= 'd0;
        r_spi_rx_data4    <= 'd0;
    end
    else begin
        r_spi_rx_cnt_done <= 1'b0;
        if(spi_sclk_neg)begin
            if(~r_spi_rx_cnt_done&&r_spi_tx_cnt_done)begin
                if((r_spi_rx_bit_cnt >= w_spi_rx_cap_first) && (r_spi_rx_bit_cnt <= w_spi_rx_cap_last))begin
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

                if(r_spi_rx_bit_cnt == w_spi_rx_done_last)begin
                    r_spi_rx_bit_cnt  <= 'd0;
                    r_spi_rx_cnt_done <= 'd1;
                    r_spi_rx_done     <= 'd1;
                end
                else begin
                    r_spi_rx_bit_cnt <= r_spi_rx_bit_cnt + 'd1;
                end
            end
        end
    end
end

always @(posedge clk_100M or negedge rst_n)begin
    if(!rst_n)begin
        r_spi_rx_done_d0 <= 1'b0;
        r_spi_rx_done_d1 <= 1'b0;
        r_spi_rx_done_d2 <= 1'b0;
        r_spi_rx_done_d3 <= 1'b0;
        r_spi_fifo_rd_en      <= 1'b0;
        r_spi_fifo_data_valid <= 1'b0;
    end
    else begin
        r_spi_rx_done_d0 <= r_spi_rx_done;
        r_spi_rx_done_d1 <= r_spi_rx_done_d0;
        r_spi_rx_done_d2 <= r_spi_rx_done_d1;
        r_spi_rx_done_d3 <= r_spi_rx_done_d2;
        r_spi_fifo_rd_en      <= r_spi_rx_done_d2 & ~r_spi_rx_done_d3;
        r_spi_fifo_data_valid <= r_spi_fifo_rd_en;
    end
end

assign  w_spi_fifo_rd_pulse = r_spi_fifo_rd_en;
assign  w_spi_rx_done_pulse = r_spi_fifo_data_valid;
assign  o_spi_rx_done       = w_spi_rx_done_pulse;

SPI_FIFO_MISO1 SPI_FIFO1_INST(
    .wr_clk(clk_160M),                // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data1),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(w_spi_fifo_rd_pulse),      // input
    .rd_data(o_spi_rx_data1),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

SPI_FIFO_MISO2 SPI_FIFO2_INST (
    .wr_clk(clk_160M),                // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data2),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(w_spi_fifo_rd_pulse),      // input
    .rd_data(o_spi_rx_data2),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

SPI_FIFO_MISO3 SPI_FIFO3_INST (
    .wr_clk(clk_160M),                // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data3),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(w_spi_fifo_rd_pulse),      // input
    .rd_data(o_spi_rx_data3),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

SPI_FIFO_MISO4 SPI_FIFO4_INST (
    .wr_clk(clk_160M),                // input
    .wr_rst(!rst_n),                  // input
    .wr_en(r_spi_rx_cnt_done),        // input
    .wr_data(r_spi_rx_data4),         // input [239:0]
    .wr_full(),                       // output
    .almost_full(),                   // output
    .rd_clk(clk_100M),                // input
    .rd_rst(!rst_n),                  // input
    .rd_en(w_spi_fifo_rd_pulse),      // input
    .rd_data(o_spi_rx_data4),         // output [239:0]
    .rd_empty(),                      // output
    .almost_empty()                   // output
);

endmodule
