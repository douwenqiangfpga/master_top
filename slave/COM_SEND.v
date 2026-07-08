module COM_SEND
(
    input              i_clk,
    input              i_rst_n /*synthesis PAP_MARK_DEBUG = "ture"*/,

    input              i_com_sclk,
    input      [15:0]  i_send_data_1 /*synthesis PAP_MARK_DEBUG = "ture"*/,
    input      [15:0]  i_send_data_2 /*synthesis PAP_MARK_DEBUG = "ture"*/,
    input      [15:0]  i_send_data_3 /*synthesis PAP_MARK_DEBUG = "ture"*/,
    input      [15:0]  i_send_data_4 /*synthesis PAP_MARK_DEBUG = "ture"*/,
    input              i_data_valid  /*synthesis PAP_MARK_DEBUG = "ture"*/,

    output reg [3:0]   o_miso        /*synthesis PAP_MARK_DEBUG = "ture"*/,
    output reg         o_send_one_word/*synthesis PAP_MARK_DEBUG = "ture"*/
);

parameter SEND_WORD_LEN = 15; //16 modified to 15

wire       w_rise_edge /*synthesis PAP_MARK_DEBUG = "ture"*/;

reg        r_com_sclk_d0;
reg [15:0] r_send_data_1 /*synthesis PAP_MARK_DEBUG = "ture"*/;
reg [15:0] r_send_data_2 /*synthesis PAP_MARK_DEBUG = "ture"*/;
reg [15:0] r_send_data_3 /*synthesis PAP_MARK_DEBUG = "ture"*/;
reg [15:0] r_send_data_4 /*synthesis PAP_MARK_DEBUG = "ture"*/;
//reg [15:0] r_data_valid /*synthesis PAP_MARK_DEBUG = "ture"*/;

assign w_rise_edge = i_com_sclk & ~r_com_sclk_d0;

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        r_com_sclk_d0 <= 1'b0;
    else
        r_com_sclk_d0 <= i_com_sclk;
end

reg [5:0] r_send_cnt /*synthesis PAP_MARK_DEBUG = "ture"*/; //send count

always @(posedge i_com_sclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_send_cnt     <= 'b0;
        o_send_one_word <= 'b0;
    end else if (i_data_valid) begin
        o_send_one_word <= 'b0;
        if (r_send_cnt >= SEND_WORD_LEN) begin
            r_send_cnt <= 0;
            o_send_one_word <= 1'b1;
        end else begin
            r_send_cnt <= r_send_cnt + 1'b1;
        end
    end else begin
        r_send_cnt <= 0;
        o_send_one_word <= 0;
    end
end

always @(posedge i_com_sclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_send_data_1 <= 'd0;
        r_send_data_2 <= 'd0;
        r_send_data_3 <= 'd0;
        r_send_data_4 <= 'd0;
    end else if (i_data_valid && (r_send_cnt == 0)) begin
        r_send_data_1 <= i_send_data_1;
        r_send_data_2 <= i_send_data_2;
        r_send_data_3 <= i_send_data_3;
        r_send_data_4 <= i_send_data_4;
    end
end

always @(posedge i_com_sclk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_miso <= 'd0;
    end else if (i_data_valid) begin
        if (r_send_cnt == 0) begin
            o_miso[0] <= i_send_data_1[15];
            o_miso[1] <= i_send_data_2[15];
            o_miso[2] <= i_send_data_3[15];
            o_miso[3] <= i_send_data_4[15];
        end else begin
            o_miso[0] <= r_send_data_1[15 - r_send_cnt] ? 1'b1 : 1'b0;
            o_miso[1] <= r_send_data_2[15 - r_send_cnt] ? 1'b1 : 1'b0;
            o_miso[2] <= r_send_data_3[15 - r_send_cnt] ? 1'b1 : 1'b0;
            o_miso[3] <= r_send_data_4[15 - r_send_cnt] ? 1'b1 : 1'b0;
        end
    end else begin
        o_miso <= 'd0;
    end
end

endmodule
