/*
主FPGA与ARM通信解析模块
        2025.8.28  创建文件
        2025.9.10  将主与ARM通信、主从通信放在一个代码里面
*/
`include "define.v"

module COM_ANALYSE(
    input               clk_160M,
    input               clk_100M,
    input               rst_n,

    //gpio输出
    output              o_gpio_sample, //给3568发送采样数据之前，先产生1个中断信号
    output              o_gpio_alarm,  //给3568发送报警信息之前，先产生1个中断信号

    //FT600Q接口
    input               i_clk_FT600,
    inout       [15:0]  io_data_FT600,
    inout       [1:0]   io_byte_enable_FT600,

    input               i_txe_n_FT600,
    input               i_rxf_n_FT600,

    output              o_wr_n_FT600,
    output              o_rd_n_FT600,
    output              o_oe_n_FT600,

    output              o_rst_n_FT600Q,
    output              o_wake_n_FT600Q,
    inout       [1:0]   io_gpio_FT600Q,

    //spi接口
    output              o_spi_sclk/*synthesis PAP_MARK_DEBUG = "1"*/,
    output              o_spi_cs/*synthesis PAP_MARK_DEBUG = "1"*/,
    output              o_spi_mosi/*synthesis PAP_MARK_DEBUG = "1"*/,
    output              o_spi_rst,

    input               i_spi_miso1/*synthesis PAP_MARK_DEBUG = "1"*/,
    input               i_spi_miso2/*synthesis PAP_MARK_DEBUG = "1"*/,
    input               i_spi_miso3/*synthesis PAP_MARK_DEBUG = "1"*/,
    input               i_spi_miso4/*synthesis PAP_MARK_DEBUG = "1"*/,
    input               i_spi_drdy,
    input               i_spi_err,

    //温度数据
    input       [31:0]  i_ads1247_data,

    //Debug
    output wire [2:0]   USB_state,
    output wire [3:0]   o_spi_state,
    output wire [4:0]   o_cmd_state
);

/********** Define Parameter and Internal Signals **********/

//主FPGA版本号
localparam      PCB_VERISON     = 16'h0100, //PCB版本号
                FPGA_TYPE       = 16'h0032, //FPGA型号
                CODE_VERISON    = 16'h0200, //程序版本号
                RESERVED_BITE   = 16'h0000; //预留位

//命令类型
localparam      RD_TYPE_CTRL    = 8'h0F, //控制
                RD_TYPE_SET     = 8'h5A, //设置
                RD_TYPE_QUER    = 8'hF1; //查询

//查询指令
localparam      RD_QUER_VER      = 8'h01, //查询FPGA版本号
                RD_QUER_ALARM    = 8'h02, //查询报警信息
                RD_QUER_ALL_DATA = 8'h10, //查询全部测试值
                RD_QUER_IR_DATA  = 8'h11, //查询内阻测试值
                RD_QUER_OCV_DATA = 8'h12, //查询电压测试值
                RD_QUER_RR_DATA  = 8'h13, //查询线阻测试值
                RD_QUER_TP_DATA  = 8'h14, //查询温度测试值
                RD_QUER_IR_ADC   = 8'h20, //查询内阻原始数据
                RD_QUER_RR_ADC   = 8'h21, //查询线阻原始数据
                RD_QUER_OCV_ADC  = 8'h22, //查询电压原始数据
                RD_QUER_TP_ADC   = 8'h23; //查询温度原始数据

reg     [4:0]   r_cmd_state /*synthesis PAP_MARK_DEBUG = "1"*/;         //指令解析状态机
reg             r_rx_fifo_rd_en /*synthesis PAP_MARK_DEBUG = "1"*/;     //接收数据fifo读使能
reg     [15:0]  r_rec_cmd_length /*synthesis PAP_MARK_DEBUG = "1"*/;    //读取数据长度
reg     [15:0]  r_rec_cmd_count/*synthesis PAP_MARK_DEBUG = "1"*/;     //已读取数据长度计数

wire    [15:0]  rx_fifo_rd_data/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            rx_fifo_empty/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            USB_rec_valid/*synthesis PAP_MARK_DEBUG = "1"*/; //可以从fifo读取接收数据

reg     [15:0]  r_send_cmd_length/*synthesis PAP_MARK_DEBUG = "1"*/; //发送数据长度
reg     [15:0]  r_send_cmd_count;  //已发送数据长度计数

//usb_state跨时钟域
reg     [2:0]   r_usb_state_r1;
reg     [2:0]   r_usb_state_r2;
reg     [2:0]   r_usb_state_r3/*synthesis PAP_MARK_DEBUG = "1"*/;
reg             r_need_rec_cmd/*synthesis PAP_MARK_DEBUG = "1"*/;       //表示有需要接收的指令
reg             r_need_spi_rx/*synthesis PAP_MARK_DEBUG = "1"*/;        //表示有需要处理的SPI回包
wire            w_usb_rec_rise_edge/*synthesis PAP_MARK_DEBUG = "1"*/;  //上升沿检测信号

reg             r_cmd_rece_done/*synthesis PAP_MARK_DEBUG = "1"*/;
reg     [47:0]  r_cmd_rece_data/*synthesis PAP_MARK_DEBUG = "1"*/;

reg             tx_fifo_wr_en;
reg     [15:0]  tx_fifo_wr_data;
wire            tx_fifo_empty;
wire            tx_fifo_full;
reg     [15:0]  usb_send_length;

reg     [15:0]  r_alarm_sig_m; //主FPGA报警信号

//spi参数定义
reg     [15:0]  r_spi_rx_bit_wide/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            w_spi_tx_st/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            w_spi_tx_done;
wire    [47:0]  w_spi_tx_data/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            w_spi_rx_done/*synthesis PAP_MARK_DEBUG = "1"*/;
wire            w_spi_cmd_busy;
reg             r_spi_busy/*synthesis PAP_MARK_DEBUG = "1"*/;

//spi接收数据
wire    [367:0] w_spi_rx_data1/*synthesis PAP_MARK_DEBUG = "1"*/;
wire    [367:0] w_spi_rx_data2/*synthesis PAP_MARK_DEBUG = "1"*/;
wire    [367:0] w_spi_rx_data3/*synthesis PAP_MARK_DEBUG = "1"*/;
wire    [367:0] w_spi_rx_data4/*synthesis PAP_MARK_DEBUG = "1"*/;

assign o_cmd_state = r_cmd_state;
assign w_spi_cmd_busy = r_spi_busy | r_cmd_rece_done;

EDGE_CKECK EDGE_CKECK_INST(
    .clk        (clk_100M             ),
    .rst_n      (rst_n                ),
    .sign       (USB_rec_valid        ),
    .rise_edge  (w_usb_rec_rise_edge  ),
    .fall_edge  (                     ),
    .both_edge  (                     )
);

//r_need_rec_cmd 需要接收ARM数据
always@(posedge clk_100M or negedge rst_n)begin
    if(!rst_n)begin
        r_need_rec_cmd <= 'd0;
    end
    else begin
        if(w_usb_rec_rise_edge)
            r_need_rec_cmd <= 'd1;
        else if(r_cmd_state == `CMD_RD_TYPE)
            r_need_rec_cmd <= 'd0;
        else
            r_need_rec_cmd <= r_need_rec_cmd;
    end
end



/************************主状态机************************/

always@(posedge clk_100M or negedge rst_n)begin
    if(!rst_n)begin
        r_cmd_state       <= `CMD_IDLE;
        r_rec_cmd_length  <= 15'd0;
        r_rec_cmd_count   <= 15'd0;
        r_cmd_rece_data   <= 48'd0;
        r_cmd_rece_done   <= 'd0;
        r_spi_rx_bit_wide <= 'd0;
        r_send_cmd_count  <= 0;
        r_send_cmd_length <= 0;
        usb_send_length   <= 0;
    end
    else begin
        case(r_cmd_state)
            `CMD_IDLE:begin //空闲状态
                r_cmd_rece_data <= 48'd0;
                r_cmd_rece_done <= 'd0;
                if(r_usb_state_r3 != `USB_IDLE) //只有在usb处于空闲时,才能进行数据接收或者数据发送
                    r_cmd_state <= r_cmd_state;
                else if(r_need_rec_cmd) begin //需要接收ARM数据
                    r_cmd_state      <= `CMD_RD_TYPE;
                    r_rec_cmd_length <= 4; //8个字节
                end
                else if(w_spi_rx_done)begin //需要接收spi数据
                    r_cmd_state <= `CMD_RX_SPI_TYPE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //接收ARM指令判断
            `CMD_RD_TYPE:begin
                if(rx_fifo_empty && (r_rec_cmd_count != r_rec_cmd_length)) begin
                    r_cmd_state     <= `CMD_ERROR;
                    r_rec_cmd_count <= 'd0;
                end
                else begin
                    r_rec_cmd_count <= r_rec_cmd_count + 'd1;
                    case(r_rec_cmd_count)
                        1:begin
                            r_cmd_rece_data[47:32] <= rx_fifo_rd_data;

                            //判断数据类型,确定spi回传时钟计数值(加26是给从FPGA时间处理数据并回传)
                            if(rx_fifo_rd_data[15:8] == RD_TYPE_CTRL)begin //控制指令
                                r_spi_rx_bit_wide <= 'd48+'d26;
                            end
                            else if(rx_fifo_rd_data[15:8] == RD_TYPE_SET)begin //设置指令
                                r_spi_rx_bit_wide <= 'd48+'d26;
                            end
                            else if(rx_fifo_rd_data[15:8] == RD_TYPE_QUER)begin //查询指令
                                if(rx_fifo_rd_data[7:0] == RD_QUER_VER) //版本号
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_TP_DATA)begin //温度数据
                                    r_cmd_state       <= `CMD_REPLY_TEMP; //回复温度数据
                                    r_spi_rx_bit_wide <= 'd0;
                                    r_rec_cmd_count   <= 0;
                                    r_rec_cmd_length  <= 0;
                                    r_send_cmd_length <= 4;
                                    usb_send_length   <= 4;
                                end
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_ALARM) //报警
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_ALL_DATA) //所有测试值
                                    r_spi_rx_bit_wide <= 'd368+'d26; //DATA1长度*16位
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_IR_DATA) //内阻数据
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_OCV_DATA) //OCV数据
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_RR_DATA) //线阻数据
                                    r_spi_rx_bit_wide <= 'd160+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_IR_ADC) //内阻原始数据
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_RR_ADC) //线阻原始数据
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                                else if(rx_fifo_rd_data[7:0] == RD_QUER_OCV_ADC) //OCV原始数据
                                    r_spi_rx_bit_wide <= 'd48+'d26;
                            end
                        end
                        2:r_cmd_rece_data[31:16] <= rx_fifo_rd_data;
                        3:r_cmd_rece_data[15:0]  <= rx_fifo_rd_data;
                        4:begin
                            r_cmd_rece_done  <= 'd1;
                            r_rec_cmd_count  <= 0;
                            r_rec_cmd_length <= 0;
                            r_cmd_state      <= `CMD_IDLE;
                        end
                        /*
                        3:begin
                            r_cmd_rece_data[15:0] <= rx_fifo_rd_data;
                            r_rec_cmd_count  <= 0;
                            r_rec_cmd_length <= 0;
                            r_cmd_state      <= `CMD_RD_ARM_DONE; //ARM数据接收完成,对指令进行解析
                        end
                        */
                        default:begin
                            r_cmd_rece_data <= r_cmd_rece_data;
                            r_cmd_state     <= r_cmd_state;
                        end
                    endcase
                end
            end

            `CMD_RD_ARM_DONE:begin
                r_cmd_rece_done <= 'd1;
                r_cmd_state     <= `CMD_IDLE;
            end

            //接收SPI数据指令相关状态机
            `CMD_RX_SPI_TYPE:begin
                if(w_spi_rx_data1[47:40] == RD_TYPE_CTRL) begin
                    r_cmd_state       <= `CMD_REPLY_CTRL; //控制指令
                    r_send_cmd_length <= 3;
                    usb_send_length   <= 3;
                end
                else if(w_spi_rx_data1[47:40] == RD_TYPE_SET) begin
                    r_cmd_state       <= `CMD_REPLY_SET; //设置指令
                    r_send_cmd_length <= 3;
                    usb_send_length   <= 3;
                end
                else if(w_spi_rx_data1[47:40] == RD_TYPE_QUER || w_spi_rx_data1[367:360] == RD_TYPE_QUER ||
                        w_spi_rx_data1[159:152] == RD_TYPE_QUER) begin
                    if(w_spi_rx_data1[359:352] == RD_QUER_ALL_DATA)begin //回复所有测试值
                        r_cmd_state       <= `CMD_REPLY_DATA;
                        r_send_cmd_length <= 86;
                        usb_send_length   <= 86;
                    end
                    else if(w_spi_rx_data1[151:144] == RD_QUER_RR_DATA)begin //回复线阻测试值
                        r_cmd_state       <= `CMD_REPLY_RR_DATA;
                        r_send_cmd_length <= 34; //18
                        usb_send_length   <= 34;
                    end
                    else if(w_spi_rx_data1[39:32] == RD_QUER_VER) begin //回复FPGA版本号
                        r_cmd_state       <= `CMD_REPLY_VER;
                        r_send_cmd_length <= 10;
                        usb_send_length   <= 10;
                    end
                    else if(w_spi_rx_data1[39:32] == RD_QUER_ALARM) begin //回复报警信息
                        r_cmd_state       <= `CMD_REPLY_ALARM;
                        r_send_cmd_length <= 4;
                        usb_send_length   <= 4;
                    end
                    else if(w_spi_rx_data1[39:32] == RD_QUER_IR_DATA || w_spi_rx_data1[39:32] == RD_QUER_RR_ADC)begin
                        r_cmd_state       <= `CMD_REPLY_Length8; //1、内阻测试值 2、线阻原始数据
                        r_send_cmd_length <= 6;
                        usb_send_length   <= 6;
                    end
                    else if(w_spi_rx_data1[39:32] == RD_QUER_OCV_DATA || w_spi_rx_data1[39:32] == RD_QUER_IR_ADC ||
                            w_spi_rx_data1[39:32] == RD_QUER_OCV_ADC) begin
                        r_cmd_state       <= `CMD_REPLY_Length4; //1、电压测试值 2、内阻原始数据 3、电压原始数据
                        r_send_cmd_length <= 4;
                        usb_send_length   <= 4;
                    end
                    else begin
                        r_cmd_state       <= `CMD_REPLY_ERROR; //没收到从FPGA数据,回复错误数据
                        r_send_cmd_length <= 3;
                        usb_send_length   <= 3;
                    end
                end
                else begin
                    r_cmd_state       <= `CMD_REPLY_ERROR; //没收到从FPGA数据,回复错误数据
                    r_send_cmd_length <= 3;
                    usb_send_length   <= 3;
                end
            end

            //回复控制指令
            `CMD_REPLY_CTRL:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复设置指令
            `CMD_REPLY_SET:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复4字节长度指令
            `CMD_REPLY_Length4:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复错误数据
            `CMD_REPLY_ERROR:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复8字节长度指令
            `CMD_REPLY_Length8:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复版本号
            `CMD_REPLY_VER:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复报警信息
            `CMD_REPLY_ALARM:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //发送所有测试数据
            `CMD_REPLY_DATA:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //发送线阻测试数据
            `CMD_REPLY_RR_DATA:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //发送温度测试数据
            `CMD_REPLY_TEMP:begin
                r_send_cmd_count <= r_send_cmd_count + 1;
                if(r_send_cmd_count == r_send_cmd_length)begin
                    r_send_cmd_count <= 0;
                    r_cmd_state      <= `CMD_REPLY_DONE;
                end
                else
                    r_cmd_state <= r_cmd_state;
            end

            //回复指令完成
            `CMD_REPLY_DONE:begin
                r_cmd_state <= `CMD_IDLE;
            end

            `CMD_ERROR: begin
                if(rx_fifo_empty == 1)
                    r_cmd_state <= `CMD_IDLE;
                else
                    r_cmd_state <= r_cmd_state;
            end
        endcase
    end
end

//USB_state
always@(posedge clk_100M or negedge rst_n) begin
    if(!rst_n) begin
        r_usb_state_r1 <= 0;
        r_usb_state_r2 <= 0;
        r_usb_state_r3 <= 0;
    end
    else begin
        r_usb_state_r1 <= /*w_usb_state*/USB_state;
        r_usb_state_r2 <= r_usb_state_r1;
        r_usb_state_r3 <= r_usb_state_r2;
    end
end

/****************USB接收数据读取控制****************/
always@(*)begin
    case(r_cmd_state)
        `CMD_RD_TYPE:begin
            if(r_rec_cmd_count < r_rec_cmd_length)
                r_rx_fifo_rd_en = 1;
            else
                r_rx_fifo_rd_en = 0;
        end
        `CMD_RD_CTRL:begin
            if(r_rec_cmd_count < r_rec_cmd_length)
                r_rx_fifo_rd_en = 1;
            else
                r_rx_fifo_rd_en = 0;
        end
        `CMD_RD_SET:begin
            if(r_rec_cmd_count < r_rec_cmd_length)
                r_rx_fifo_rd_en = 1;
            else
                r_rx_fifo_rd_en = 0;
        end
        `CMD_RD_QUER:begin
            if(r_rec_cmd_count < r_rec_cmd_length)
                r_rx_fifo_rd_en = 1;
            else
                r_rx_fifo_rd_en = 0;
        end
        `CMD_RD_QUER_TEMP:begin
            if(r_rec_cmd_count < r_rec_cmd_length)
                r_rx_fifo_rd_en = 1;
            else
                r_rx_fifo_rd_en = 0;
        end
        `CMD_REPLY_TEMP: begin //查询温度数据,要把剩余的值全部读出来
            if(rx_fifo_empty)
                r_rx_fifo_rd_en = 0;
            else
                r_rx_fifo_rd_en = 1;
        end
        `CMD_ERROR: begin //error状态下,要把剩下的错误数据全部读出来
            if(rx_fifo_empty)
                r_rx_fifo_rd_en = 0;
            else
                r_rx_fifo_rd_en = 1;
        end
        default:
            r_rx_fifo_rd_en = 0;
    endcase
end

/*--------------------主FPGA发送数据控制--------------------*/
//tx_fifo 写使能控制
always@(posedge clk_100M)begin
    case(r_cmd_state)
        `CMD_REPLY_SET:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_CTRL:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_Length4:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_Length8:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_VER:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_ALARM:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_DATA:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_RR_DATA:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_TEMP:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_ERROR:begin
            if(r_send_cmd_count == r_send_cmd_length)
                tx_fifo_wr_en = 0;
            else
                tx_fifo_wr_en = 1;
        end
        `CMD_REPLY_DONE:
            tx_fifo_wr_en = 0;
        default:
            tx_fifo_wr_en = 0;
    endcase
end

//tx_fifo 写入数据控制
always@(*)begin
    case(r_cmd_state)
        `CMD_REPLY_SET:begin //回复设置指令
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = w_spi_rx_data1[47:32];
                2:tx_fifo_wr_data = w_spi_rx_data1[31:16];
                3:tx_fifo_wr_data = w_spi_rx_data1[15:0];
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_CTRL:begin //回复控制指令
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = w_spi_rx_data1[47:32];
                2:tx_fifo_wr_data = w_spi_rx_data1[31:16];
                3:tx_fifo_wr_data = w_spi_rx_data1[15:0];
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_Length4:begin //回复4字节指令
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = w_spi_rx_data1[47:32];
                2:tx_fifo_wr_data = 16'h0004; //字节长度
                3:tx_fifo_wr_data = w_spi_rx_data1[15:0];
                4:tx_fifo_wr_data = w_spi_rx_data2[15:0];
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_ERROR:begin //回复错误数据
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = w_spi_rx_data1[47:32]; //16'hF102;
                2:tx_fifo_wr_data = w_spi_rx_data1[31:16]; //16'h0002; //字节长度
                3:tx_fifo_wr_data = w_spi_rx_data1[15:0];  //16'h0099;
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_Length8:begin //回复8字节指令
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = w_spi_rx_data1[47:32];
                2:tx_fifo_wr_data = 16'h0008; //字节长度
                3:tx_fifo_wr_data = w_spi_rx_data1[15:0];
                4:tx_fifo_wr_data = w_spi_rx_data2[15:0];
                5:tx_fifo_wr_data = w_spi_rx_data3[15:0];
                6:tx_fifo_wr_data = w_spi_rx_data4[15:0];
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_VER:begin //主FPGA版本号回复
            case(r_send_cmd_count)
                1:tx_fifo_wr_data  = w_spi_rx_data1[47:32];
                2:tx_fifo_wr_data  = 16'h0010; //字节长度
                3:tx_fifo_wr_data  = PCB_VERISON;
                4:tx_fifo_wr_data  = FPGA_TYPE;
                5:tx_fifo_wr_data  = CODE_VERISON;
                6:tx_fifo_wr_data  = RESERVED_BITE;
                7:tx_fifo_wr_data  = w_spi_rx_data1[15:0];
                8:tx_fifo_wr_data  = w_spi_rx_data2[15:0];
                9:tx_fifo_wr_data  = w_spi_rx_data3[15:0];
                10:tx_fifo_wr_data = w_spi_rx_data4[15:0];
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_ALARM:begin //报警信息回复
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = w_spi_rx_data1[47:32];
                2:tx_fifo_wr_data = 16'h0004; //字节长度
                3:tx_fifo_wr_data = 16'h0000/*r_alarm_sig_m*/; //主FPGA报警信息
                4:tx_fifo_wr_data = w_spi_rx_data1[15:0];      //从FPGA报警信息
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_TEMP:begin //温度数据回复
            case(r_send_cmd_count)
                1:tx_fifo_wr_data = 16'hF114;
                2:tx_fifo_wr_data = 16'h0004;             //字节长度
                3:tx_fifo_wr_data = i_ads1247_data[31:16]; //温度数据高
                4:tx_fifo_wr_data = i_ads1247_data[15:0];  //温度数据低
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_DATA:begin //所有测试值回复
            case(r_send_cmd_count)
                1 :tx_fifo_wr_data = w_spi_rx_data1[367:352]; //命令类型
                2 :tx_fifo_wr_data = 16'h00A8;                //字节长度[351:336]

                3 :tx_fifo_wr_data = w_spi_rx_data1[335:320];
                4 :tx_fifo_wr_data = w_spi_rx_data2[335:320];
                5 :tx_fifo_wr_data = w_spi_rx_data3[335:320];
                6 :tx_fifo_wr_data = w_spi_rx_data4[335:320];

                7 :tx_fifo_wr_data = w_spi_rx_data1[319:304];
                8 :tx_fifo_wr_data = w_spi_rx_data2[319:304];
                9 :tx_fifo_wr_data = w_spi_rx_data3[319:304];
                10:tx_fifo_wr_data = w_spi_rx_data4[319:304];

                11:tx_fifo_wr_data = w_spi_rx_data1[303:288];
                12:tx_fifo_wr_data = w_spi_rx_data2[303:288];
                13:tx_fifo_wr_data = w_spi_rx_data3[303:288];
                14:tx_fifo_wr_data = w_spi_rx_data4[303:288];

                15:tx_fifo_wr_data = w_spi_rx_data1[287:272];
                16:tx_fifo_wr_data = w_spi_rx_data2[287:272];
                17:tx_fifo_wr_data = w_spi_rx_data3[287:272];
                18:tx_fifo_wr_data = w_spi_rx_data4[287:272];

                19:tx_fifo_wr_data = w_spi_rx_data1[271:256];
                20:tx_fifo_wr_data = w_spi_rx_data2[271:256];
                21:tx_fifo_wr_data = w_spi_rx_data3[271:256];
                22:tx_fifo_wr_data = w_spi_rx_data4[271:256];

                23:tx_fifo_wr_data = w_spi_rx_data1[255:240]; //IR_REAL[63:48]
                24:tx_fifo_wr_data = w_spi_rx_data2[255:240]; //IR_REAL[47:32]
                25:tx_fifo_wr_data = w_spi_rx_data3[255:240]; //IR_REAL[31:16]
                26:tx_fifo_wr_data = w_spi_rx_data4[255:240]; //IR_REAL[15:0]

                27:tx_fifo_wr_data = w_spi_rx_data1[239:224]; //IR_REAL[63:48]
                28:tx_fifo_wr_data = w_spi_rx_data2[239:224]; //IR_REAL[47:32]
                29:tx_fifo_wr_data = w_spi_rx_data3[239:224]; //IR_REAL[31:16]
                30:tx_fifo_wr_data = w_spi_rx_data4[239:224]; //IR_REAL[15:0]

                31:tx_fifo_wr_data = w_spi_rx_data1[223:208]; //IR_REAL[63:48]
                32:tx_fifo_wr_data = w_spi_rx_data2[223:208]; //IR_REAL[47:32]
                33:tx_fifo_wr_data = w_spi_rx_data3[223:208]; //IR_REAL[31:16]
                34:tx_fifo_wr_data = w_spi_rx_data4[223:208]; //IR_REAL[15:0]

                35:tx_fifo_wr_data = w_spi_rx_data1[207:192]; //IR_REAL[63:48]
                36:tx_fifo_wr_data = w_spi_rx_data2[207:192]; //IR_REAL[47:32]
                37:tx_fifo_wr_data = w_spi_rx_data3[207:192]; //IR_REAL[31:16]
                38:tx_fifo_wr_data = w_spi_rx_data4[207:192]; //IR_REAL[15:0]

                39:tx_fifo_wr_data = w_spi_rx_data1[191:176]; //IR_IMAG[63:48]
                40:tx_fifo_wr_data = w_spi_rx_data2[191:176]; //IR_IMAG[47:32]
                41:tx_fifo_wr_data = w_spi_rx_data3[191:176]; //IR_IMAG[31:16]
                42:tx_fifo_wr_data = w_spi_rx_data4[191:176]; //IR_IMAG[15:0]

                43:tx_fifo_wr_data = w_spi_rx_data1[175:160]; //REF_REAL[63:48]
                44:tx_fifo_wr_data = w_spi_rx_data2[175:160]; //REF_REAL[47:32]
                45:tx_fifo_wr_data = w_spi_rx_data3[175:160]; //REF_REAL[31:16]
                46:tx_fifo_wr_data = w_spi_rx_data4[175:160]; //REF_REAL[15:0]

                47:tx_fifo_wr_data = w_spi_rx_data1[159:144]; //REF_IMAG[63:48]
                48:tx_fifo_wr_data = w_spi_rx_data2[159:144]; //REF_IMAG[47:32]
                49:tx_fifo_wr_data = w_spi_rx_data3[159:144]; //REF_IMAG[31:16]
                50:tx_fifo_wr_data = w_spi_rx_data4[159:144]; //REF_IMAG[15:0]

                51:tx_fifo_wr_data = w_spi_rx_data1[143:128]; //OCV_H
                52:tx_fifo_wr_data = w_spi_rx_data2[143:128]; //OCV_L
                53:tx_fifo_wr_data = w_spi_rx_data3[143:128]; //OCV_H
                54:tx_fifo_wr_data = w_spi_rx_data4[143:128]; //OCV_L

                55:tx_fifo_wr_data = w_spi_rx_data1[127:112]; //H_SOURCE_REAL[63:48]
                56:tx_fifo_wr_data = w_spi_rx_data2[127:112]; //H_SOURCE_REAL[47:32]
                57:tx_fifo_wr_data = w_spi_rx_data3[127:112]; //H_SOURCE_REAL[31:16]
                58:tx_fifo_wr_data = w_spi_rx_data4[127:112]; //H_SOURCE_REAL[15:0]

                59:tx_fifo_wr_data = w_spi_rx_data1[111:96]; //H_SOURCE_IMAG[63:48]
                60:tx_fifo_wr_data = w_spi_rx_data2[111:96]; //H_SOURCE_IMAG[47:32]
                61:tx_fifo_wr_data = w_spi_rx_data3[111:96]; //H_SOURCE_IMAG[31:16]
                62:tx_fifo_wr_data = w_spi_rx_data4[111:96]; //H_SOURCE_IMAG[15:0]

                63:tx_fifo_wr_data = w_spi_rx_data1[95:80]; //L_SOURCE_REAL[63:48]
                64:tx_fifo_wr_data = w_spi_rx_data2[95:80]; //L_SOURCE_REAL[47:32]
                65:tx_fifo_wr_data = w_spi_rx_data3[95:80]; //L_SOURCE_REAL[31:16]
                66:tx_fifo_wr_data = w_spi_rx_data4[95:80]; //L_SOURCE_REAL[15:0]

                67:tx_fifo_wr_data = w_spi_rx_data1[79:64]; //L_SOURCE_IMAG[63:48]
                68:tx_fifo_wr_data = w_spi_rx_data2[79:64]; //L_SOURCE_IMAG[47:32]
                69:tx_fifo_wr_data = w_spi_rx_data3[79:64]; //L_SOURCE_IMAG[31:16]
                70:tx_fifo_wr_data = w_spi_rx_data4[79:64]; //L_SOURCE_IMAG[15:0]

                71:tx_fifo_wr_data = w_spi_rx_data1[63:48]; //H_SENCE_REAL[63:48]
                72:tx_fifo_wr_data = w_spi_rx_data2[63:48]; //H_SENCE_REAL[47:32]
                73:tx_fifo_wr_data = w_spi_rx_data3[63:48]; //H_SENCE_REAL[31:16]
                74:tx_fifo_wr_data = w_spi_rx_data4[63:48]; //H_SENCE_REAL[15:0]

                75:tx_fifo_wr_data = w_spi_rx_data1[47:32]; //H_SENCE_IMAG[63:48]
                76:tx_fifo_wr_data = w_spi_rx_data2[47:32]; //H_SENCE_IMAG[47:32]
                77:tx_fifo_wr_data = w_spi_rx_data3[47:32]; //H_SENCE_IMAG[31:16]
                78:tx_fifo_wr_data = w_spi_rx_data4[47:32]; //H_SENCE_IMAG[15:0]

                79:tx_fifo_wr_data = w_spi_rx_data1[31:16]; //L_SENCE_REAL[63:48]
                80:tx_fifo_wr_data = w_spi_rx_data2[31:16]; //L_SENCE_REAL[47:32]
                81:tx_fifo_wr_data = w_spi_rx_data3[31:16]; //L_SENCE_REAL[31:16]
                82:tx_fifo_wr_data = w_spi_rx_data4[31:16]; //L_SENCE_REAL[15:0]

                83:tx_fifo_wr_data = w_spi_rx_data1[15:0]; //L_SENCE_IMAG[63:48]
                84:tx_fifo_wr_data = w_spi_rx_data2[15:0]; //L_SENCE_IMAG[47:32]
                85:tx_fifo_wr_data = w_spi_rx_data3[15:0]; //L_SENCE_IMAG[31:16]
                86:tx_fifo_wr_data = w_spi_rx_data4[15:0]; //L_SENCE_IMAG[15:0]
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        `CMD_REPLY_RR_DATA:begin //所有线阻测试值回复
            case(r_send_cmd_count)
                1 :tx_fifo_wr_data = w_spi_rx_data1[159:144]; //命令类型
                2 :tx_fifo_wr_data = 16'h0038;                //字节长度

                3 :tx_fifo_wr_data = w_spi_rx_data1[127:112]; //H_SOURCE_REAL[63:48]
                4 :tx_fifo_wr_data = w_spi_rx_data2[127:112]; //H_SOURCE_REAL[47:32]
                5 :tx_fifo_wr_data = w_spi_rx_data3[127:112]; //H_SOURCE_REAL[31:16]
                6 :tx_fifo_wr_data = w_spi_rx_data4[127:112]; //H_SOURCE_REAL[15:0]

                7 :tx_fifo_wr_data = w_spi_rx_data1[111:96]; //H_SOURCE_IMAG[63:48]
                8 :tx_fifo_wr_data = w_spi_rx_data2[111:96]; //H_SOURCE_IMAG[47:32]
                9 :tx_fifo_wr_data = w_spi_rx_data3[111:96]; //H_SOURCE_IMAG[31:16]
                10:tx_fifo_wr_data = w_spi_rx_data4[111:96]; //H_SOURCE_IMAG[15:0]

                11:tx_fifo_wr_data = w_spi_rx_data1[95:80]; //L_SOURCE_REAL[63:48]
                12:tx_fifo_wr_data = w_spi_rx_data2[95:80]; //L_SOURCE_REAL[47:32]
                13:tx_fifo_wr_data = w_spi_rx_data3[95:80]; //L_SOURCE_REAL[31:16]
                14:tx_fifo_wr_data = w_spi_rx_data4[95:80]; //L_SOURCE_REAL[15:0]

                15:tx_fifo_wr_data = w_spi_rx_data1[79:64]; //L_SOURCE_IMAG[63:48]
                16:tx_fifo_wr_data = w_spi_rx_data2[79:64]; //L_SOURCE_IMAG[47:32]
                17:tx_fifo_wr_data = w_spi_rx_data3[79:64]; //L_SOURCE_IMAG[31:16]
                18:tx_fifo_wr_data = w_spi_rx_data4[79:64]; //L_SOURCE_IMAG[15:0]

                19:tx_fifo_wr_data = w_spi_rx_data1[63:48]; //H_SENCE_REAL[63:48]
                20:tx_fifo_wr_data = w_spi_rx_data2[63:48]; //H_SENCE_REAL[47:32]
                21:tx_fifo_wr_data = w_spi_rx_data3[63:48]; //H_SENCE_REAL[31:16]
                22:tx_fifo_wr_data = w_spi_rx_data4[63:48]; //H_SENCE_REAL[15:0]

                23:tx_fifo_wr_data = w_spi_rx_data1[47:32]; //H_SENCE_IMAG[63:48]
                24:tx_fifo_wr_data = w_spi_rx_data2[47:32]; //H_SENCE_IMAG[47:32]
                25:tx_fifo_wr_data = w_spi_rx_data3[47:32]; //H_SENCE_IMAG[31:16]
                26:tx_fifo_wr_data = w_spi_rx_data4[47:32]; //H_SENCE_IMAG[15:0]

                27:tx_fifo_wr_data = w_spi_rx_data1[31:16]; //L_SENCE_REAL[63:48]
                28:tx_fifo_wr_data = w_spi_rx_data2[31:16]; //L_SENCE_REAL[47:32]
                29:tx_fifo_wr_data = w_spi_rx_data3[31:16]; //L_SENCE_REAL[31:16]
                30:tx_fifo_wr_data = w_spi_rx_data4[31:16]; //L_SENCE_REAL[15:0]

                31:tx_fifo_wr_data = w_spi_rx_data1[15:0]; //L_SENCE_IMAG[63:48]
                32:tx_fifo_wr_data = w_spi_rx_data2[15:0]; //L_SENCE_IMAG[47:32]
                33:tx_fifo_wr_data = w_spi_rx_data3[15:0]; //L_SENCE_IMAG[31:16]
                34:tx_fifo_wr_data = w_spi_rx_data4[15:0]; //L_SENCE_IMAG[15:0]
                default: tx_fifo_wr_data = 16'h0000;
            endcase
        end

        default:
            tx_fifo_wr_data = 16'h0000;
    endcase
end

/***********************FT600Q调用************************/
//数据发送使能控制
reg             USB_send_en;
wire            USB_send_en_expand;
always@(*) begin
    case(r_cmd_state)
        `CMD_REPLY_DONE:
            USB_send_en = 1;
        default:
            USB_send_en = 0;
    endcase
end

//脉宽扩展
PULSE_EXPAND#(
    .EXPAND_NUM(3)
)PULSE_EXPAND_INST(
    .clk        (clk_100M           ),
    .rst_n      (rst_n              ),
    .sig_in     (USB_send_en        ),
    .sig_out    (USB_send_en_expand )
);

//FT600Q_DRIVE
FT600Q_DRIVE FT600Q_DRIVE_INST(
    .clk_100M            (clk_100M           ),
    .rst_n               (rst_n              ),

    //控制信号
    .USB_send_en         (USB_send_en_expand ), //可以发送数据,信号需要被600Q的clk捕获,信号需要拓宽
    .usb_send_length     (usb_send_length    ),
    .USB_rec_valid       (USB_rec_valid      ), /*synthesis PAP_MARK_DEBUG = "1"*/ //可以从fifo读取接收数据

    //FT600 接口
    .clk_FT600           (i_clk_FT600        ),
    .data_FT600          (io_data_FT600      ),
    .byte_enable_FT600   (io_byte_enable_FT600),
    .txe_n_FT600         (i_txe_n_FT600      ),
    .rxf_n_FT600         (i_rxf_n_FT600      ),
    .wr_n_FT600          (o_wr_n_FT600       ),
    .rd_n_FT600          (o_rd_n_FT600       ),
    .oe_n_FT600          (o_oe_n_FT600       ),

    //数据发送fifo接口
    .tx_fifo_wr_en       (tx_fifo_wr_en      ),
    .tx_fifo_wr_data     (tx_fifo_wr_data    ),
    .tx_fifo_empty       (tx_fifo_empty      ), //只有发送fifo为空时才能向FIFO里写入数据
    .tx_fifo_full        (tx_fifo_full       ),

    //数据接收fifo接口
    .rx_fifo_rd_en       (r_rx_fifo_rd_en    ),
    .rx_fifo_rd_data     (rx_fifo_rd_data    ),
    .rx_fifo_empty       (rx_fifo_empty      ),

    .USB_state           (USB_state          )
);

/***********************SPI驱动调用************************/
SPI_DRIVE SPI_DRIVE_INST(
    .clk_160M       (clk_160M          ),
    .clk_100M       (clk_100M          ),
    .rst_n          (rst_n             ),

    //spi输出信号
    .o_spi_sclk     (o_spi_sclk        ),
    .o_spi_cs       (o_spi_cs          ),
    .o_spi_mosi     (o_spi_mosi        ),

    .i_spi_tx_data  (w_spi_tx_data     ),
    .i_spi_tx_st    (w_spi_tx_st       ),
    .i_spi_rx_bit_wide(r_spi_rx_bit_wide),
    .o_spi_tx_done  (w_spi_tx_done     ),

    //spi输入信号
    .i_spi_miso1    (i_spi_miso1       ),
    .i_spi_miso2    (i_spi_miso2       ),
    .i_spi_miso3    (i_spi_miso3       ),
    .i_spi_miso4    (i_spi_miso4       ),

    //from_slave_data
    .o_spi_rx_data1 (w_spi_rx_data1    ),
    .o_spi_rx_data2 (w_spi_rx_data2    ),
    .o_spi_rx_data3 (w_spi_rx_data3    ),
    .o_spi_rx_data4 (w_spi_rx_data4    ),
    .o_spi_rx_done  (w_spi_rx_done     ),

    .o_spi_state    (o_spi_state       )
);

/*************spi发送从FPGA指令控制*************/
//reg [47:0] r_spi_tx_data/*synthesis PAP_MARK_DEBUG = "1"*/;
//reg        r_spi_tx_st/*synthesis PAP_MARK_DEBUG = "1"*/;
//
//always @(posedge clk_100M or negedge rst_n) begin
//    if(!rst_n)begin
//        r_spi_tx_data <= 48'd0;
//        r_spi_tx_st   <= 1'b0;
//    end
//    else begin
//        r_spi_tx_st <= 1'b0;
//        if(r_cmd_rece_done && (r_spi_rx_bit_wide != 16'd0))begin
//            r_spi_tx_data <= r_cmd_rece_data;
//            r_spi_tx_st   <= 1'b1;
//        end
//    end
//end
//
//assign w_spi_tx_data = r_spi_tx_data;
//
//assign  w_spi_tx_st   = r_spi_tx_st;
reg         r_cmd_rece_done1/*synthesis PAP_MARK_DEBUG = "1"*/;
reg         r_cmd_rece_done2/*synthesis PAP_MARK_DEBUG = "1"*/;

always @(posedge clk_100M or negedge rst_n) begin
    if(!rst_n)begin
        r_cmd_rece_done1 <= 1'b0;
        r_cmd_rece_done2 <= 1'b0;
    end
    else begin
        r_cmd_rece_done1 <= r_cmd_rece_done;
        r_cmd_rece_done2 <= r_cmd_rece_done1;
    end

end

assign  w_spi_tx_st   = r_cmd_rece_done; //上升沿触发
assign w_spi_tx_data = r_cmd_rece_done ? r_cmd_rece_data : w_spi_tx_data;



/***************FT600Q信号控制****************/
assign  o_gpio_sample  = i_spi_drdy; //从FPGA数据已准备好
assign  o_gpio_alarm   = i_spi_err;  //FPGA产生报警信息(可增加主FPGA报警信号,和从FPGA一块产生报警信息)
assign  o_rst_n_FT600Q = rst_n;
assign  o_wake_n_FT600Q = 0;
assign  io_gpio_FT600Q = 2'b00;

/***************SPI信号控制****************/
assign  o_spi_rst = rst_n;

endmodule
