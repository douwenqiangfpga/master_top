`include "define.v"

module FT600Q_DRIVE(
    input              clk_100M,
    input              rst_n,

    //控制信号
    input              USB_send_en/*synthesis PAP_MARK_DEBUG = "1"*/,        //可以发送数据,信号需要被600Q的clk捕获, 信号需要拓宽
    input      [15:0]  usb_send_length/*synthesis PAP_MARK_DEBUG = "1"*/,    //数据发送长度
    output             USB_rec_valid/*synthesis PAP_MARK_DEBUG = "1"*/ ,     //可以从fifo读取接收数据, 宽度为3个clk_FT600Q周期

    //FT600 接口
    input              clk_FT600/*synthesis PAP_MARK_DEBUG = "1"*/,
    inout      [15:0]  data_FT600/*synthesis PAP_MARK_DEBUG = "1"*/ ,
    inout      [1:0]   byte_enable_FT600,/*synthesis PAP_MARK_DEBUG = "1"*/
    input              txe_n_FT600, /*synthesis PAP_MARK_DEBUG = "1"*/
    input              rxf_n_FT600, /*synthesis PAP_MARK_DEBUG = "1"*/
    output             wr_n_FT600,/*synthesis PAP_MARK_DEBUG = "1"*/
    output             rd_n_FT600,/*synthesis PAP_MARK_DEBUG = "1"*/
    output             oe_n_FT600,/*synthesis PAP_MARK_DEBUG = "1"*/

    //数据发送fifo接口
    input              tx_fifo_wr_en,   /*synthesis PAP_MARK_DEBUG = "1"*/
    input      [15:0]  tx_fifo_wr_data, /*synthesis PAP_MARK_DEBUG = "1"*/
    output             tx_fifo_empty,   //只有发送fifo为空时才能向FIFO里写入数据
    output             tx_fifo_full,

    //数据接收fifo接口
    input              rx_fifo_rd_en,/*synthesis PAP_MARK_DEBUG = "1"*/
    output     [15:0]  rx_fifo_rd_data,/*synthesis PAP_MARK_DEBUG = "1"*/
    input              rx_fifo_rd_rst,
    output             rx_fifo_empty/*synthesis PAP_MARK_DEBUG = "1"*/,

    output reg [2:0]   USB_state/*synthesis PAP_MARK_DEBUG = "1"*/
);

reg             USB_rec_valid_r;
reg     [15:0]  usb_send_data_count/*synthesis PAP_MARK_DEBUG = "1"*/;//已发送数据计数
reg     [15:0]  usb_send_length_r/*synthesis PAP_MARK_DEBUG = "1"*/;//待发送数据长度 16383数据长度
reg             USB_send_en_rise_r;
reg     [15:0]  data_ft600_temp/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             tx_fifo_rd_en1='d0;
reg             tx_fifo_rd_en2='d0;

wire    [15:0]  ft600data_debug;/*synthesis PAP_MARK_DEBUG = "1"*/
assign          ft600data_debug = data_FT600;

/*-----------------------------数据发送fifo-----------------------------*/

//数据发送给ARM, 查询的数据先经过数据发送FIFO,再读取FIFO的数据,然后赋值给FT600Q
//宽度16, 深度4096
wire            tx_fifo_rd_en;/*synthesis PAP_MARK_DEBUG = "1"*/
wire    [15:0]  tx_fifo_rd_data;/*synthesis PAP_MARK_DEBUG = "1"*/

//在数据发送状态, 只要600Q还有空闲空间, 就持续读取FIFO里的数据
assign tx_fifo_rd_en=((USB_state==`USB_TX)&&(usb_send_data_count<usb_send_length_r)&&(txe_n_FT600==0)) ? 1:0;

//在数据发送状态, 只要FIFO里还有数据, 就拉高写使能
assign wr_n_FT600=((USB_state==`USB_TX||USB_state==`USB_TX_LAST)&&(txe_n_FT600==0)&&tx_fifo_rd_en2)? 0:1;

FIFO_TX FIFO_TX_INST(
    .wr_clk        (clk_100M         ),        // input
    .wr_rst        (!rst_n           ),        // input
    .wr_en         (tx_fifo_wr_en    ),        // input
    .wr_data       (tx_fifo_wr_data  ),        // input [15:0]
    .wr_full       (tx_fifo_full     ),        // output
    .almost_full   (                 ),        // output

    .rd_clk        (~clk_FT600       ),        // input
    .rd_rst        (!rst_n           ),        // input
    .rd_en         (tx_fifo_rd_en    ),        // input
    .rd_data       (tx_fifo_rd_data  ),        // output [15:0]
    .rd_empty      (tx_fifo_empty    ),        // output
    .almost_empty  (                 )         // output
);

/*-----------------------------数据接收fifo-----------------------------*/
//数据接收FIFO是接收来自ARM的数据, 然后进行解析, 转发给从FPGA
wire            rx_fifo_full; /*synthesis PAP_MARK_DEBUG = "1"*/
wire            rx_fifo_wr_en; /*synthesis PAP_MARK_DEBUG = "1"*/
wire    [15:0]  rx_fifo_wr_data; /*synthesis PAP_MARK_DEBUG = "1"*/

//在数据接收状态,FIFO没满, 且USB数据有效时进行数据写入
assign rx_fifo_wr_en=((USB_state==`USB_RX)&&(rx_fifo_full==0)&&(rxf_n_FT600==0))? 1:0;
//数据接收状态下, 把USB接口的数据连接奥fifo1写入数据上
assign rx_fifo_wr_data=(USB_state==`USB_RX )? data_FT600:16'b0;
//宽度16, 深度256
FIFO_RX FIFO_RX_INST (
    .wr_clk        (clk_FT600        ),        // input
    .wr_rst        (!rst_n           ),        // input
    .wr_en         (rx_fifo_wr_en    ),        // input
    .wr_data       (rx_fifo_wr_data  ),        // input [15:0]
    .wr_full       (rx_fifo_full     ),        // output
    .almost_full   (                 ),        // output

    .rd_clk        (clk_100M         ),        // input
    .rd_rst        (!rst_n           ),        // input
    .rd_en         (rx_fifo_rd_en    ),        // input
    .rd_data       (rx_fifo_rd_data  ),        // output [15:0]
    .rd_empty      (rx_fifo_empty    ),        // output
    .almost_empty  (                 )         // output
);

/*-----------------------------输入信号转换-----------------------------*/
//txe_n,rxf_n,data以及be作为输入信号时, 是在clk的下降沿发生变化, 因此需要在上升沿时记录信号状态
reg             txe_n_r;
reg             rxf_n_r;

always@(posedge clk_FT600 or negedge rst_n)begin
    if(!rst_n)begin
        txe_n_r<=1;
        rxf_n_r<=1;
    end
    else begin
        txe_n_r<=/*~USB_send_en_rise_r*/txe_n_FT600; //经过缓存后, 现在输入信号变为在上升沿时变化, 此时可以在下降沿读取信号状态
        rxf_n_r<=rxf_n_FT600;
    end
end

//USB_send_en是clk_100M时钟域下的信号, 宽度3个clk, 需要做上升沿检测
reg             USB_send_en_r1/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             USB_send_en_r2/*synthesis PAP_MARK_DEBUG = "1"*/;

always@(negedge clk_FT600 or negedge rst_n)begin
    if(!rst_n)begin
        USB_send_en_r1 <= 'd0;
        USB_send_en_r2 <= 'd0;
    end
    else begin
        USB_send_en_r1 <= USB_send_en;
        USB_send_en_r2 <= USB_send_en_r1;
    end
end

wire            USB_send_en_rise/*synthesis PAP_MARK_DEBUG = "1"*/;

assign          USB_send_en_rise = ((USB_send_en_r1==1)&&(USB_send_en_r2==0))? 1:0;

//对USB_send_en_rise的上升沿进行缓存
always@(negedge clk_FT600 or negedge rst_n)begin
    if(!rst_n)begin
        USB_send_en_rise_r <= 'd0;
    end
    else begin
        if(USB_send_en_rise)begin
            USB_send_en_rise_r <= 'd1;   //表示有数据需要发送, 防止正在接收数据时出现发送请求
        end
        if(USB_state == `USB_TX_LAST)begin //表示数据已经被发送
            USB_send_en_rise_r <= 'd0;
        end
    end
end

//发送数据缓存
always@(negedge clk_FT600 or negedge rst_n)begin
    if(!rst_n)begin
        usb_send_length_r <= 'd0;
    end
    else begin
        usb_send_length_r <= usb_send_length;
    end
end

/*-----------------------------状态机-----------------------------*/
always@(negedge clk_FT600 or negedge rst_n)begin //边沿检测待定
    if(!rst_n)begin
        USB_state <= `USB_IDLE;
        USB_rec_valid_r <= 'd0;
        usb_send_data_count <= 'd0;
    end
    else begin
        USB_rec_valid_r <= 'd0;
        case(USB_state)
            `USB_IDLE:begin
                if(USB_send_en_rise_r && (txe_n_r == 'd0))     //有过有效数据需要被发送
                    USB_state <= `USB_TX_PRE;
                else if(rxf_n_r == 'd0)    //表示600Q有数据待读取
                    USB_state <= `USB_OE;
                else
                    USB_state <= USB_state;
            end
            `USB_TX_PRE:     //在这个状态, 提前拉高tx_fifo的读使能1个clk
                USB_state <= `USB_TX;
            `USB_TX:begin
                if(txe_n_FT600 == 'd0)begin
                    if(usb_send_data_count == usb_send_length_r)begin//如果FIFO读空, 也就是需要发送的数据已全部发走
                        USB_state <= `USB_TX_LAST;
                        usb_send_data_count <= 'd0;
                    end
                    else begin
                        usb_send_data_count <= usb_send_data_count + 'd1;
                        USB_state <= USB_state;
                    end
                end
                else begin
                    USB_state <= USB_state;
                    usb_send_data_count <= usb_send_data_count;
                end
            end
            `USB_TX_LAST://发送tx fifo里的最后一个数据
                USB_state <= `USB_IDLE;
            `USB_OE:      //oe使能
                USB_state <= `USB_RX_PRE;
                //USB_state <= `USB_RX;
            `USB_RX_PRE: //rd_n使能
                USB_state <= `USB_RX;
            `USB_RX: begin //开始接收数据
                if(rxf_n_r)begin  //rxf_n_r拉高表示USB接收数据读取完成
                    USB_state <= `USB_IDLE;
                    USB_rec_valid_r <= 'd1;
                end
                else
                    USB_state <= USB_state;
            end
            default:
                USB_state <= `USB_IDLE;
        endcase
    end
end

/*-----------------------------输出信号拓宽-----------------------------*/
PULSE_EXPAND#(
    .EXPAND_NUM(2) //脉宽拓展2个clk_FT600,共3个clk_FT600时钟,保证在100M时钟下可以稳定读取到有效信号
)PULSE_EXPAND_INST(
    .clk        (clk_FT600       ),
    .rst_n      (rst_n           ),
    .sig_in     (USB_rec_valid_r ),
    .sig_out    (USB_rec_valid   )
);

/*-----------------------------输出接口控制-----------------------------*/
always @(negedge clk_FT600 or negedge rst_n)begin
    if(!rst_n)
        data_ft600_temp <= 16'd0;
    else if(USB_state==`USB_TX)
        data_ft600_temp <= tx_fifo_rd_data;
    else
        data_ft600_temp <= 16'd0;
end

always @(negedge clk_FT600)begin
    tx_fifo_rd_en1 <= tx_fifo_rd_en;
    tx_fifo_rd_en2 <= tx_fifo_rd_en1;
end

assign      data_FT600 = (((USB_state==`USB_TX)||(USB_state==`USB_TX_LAST))&&tx_fifo_rd_en2)? data_ft600_temp:16'bZ;
assign      byte_enable_FT600 = (((USB_state==`USB_TX)||(USB_state==`USB_TX_LAST))&&tx_fifo_rd_en2)? 2'b11:2'bZ;

assign      oe_n_FT600 = ((USB_state==`USB_OE)||(USB_state==`USB_RX)||(USB_state==`USB_RX_PRE))? 0:1;
assign      rd_n_FT600 = ((USB_state==`USB_RX)||(USB_state==`USB_RX_PRE))? 0:1;

endmodule
