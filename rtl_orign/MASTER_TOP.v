/*
主FPGA顶层文件
Author:王建冲
MASTER_TOP:
    (1)主时钟100Mhz
    (2)主要功能：通信中转、温度采集、部分控制
*/
module MASTER_TOP(
    input               i_clk_osc, //晶振50Mhz

    output wire         o_led1,
    output wire         o_led2,

    //gpio输出
    output              o_gpio_master_data/*synthesis PAP_MARK_DEBUG = "1"*/, //主FPGA温度数据完成
    output              o_gpio_host_data/*synthesis PAP_MARK_DEBUG = "1"*/,   //从FPGA数据准备完成
    output              o_gpio_alarm,                                          //从FPGA报警信号

    //温度预警
    input               i_tmp302_flag,

    //主从FPGA通信
    output              o_spi_sclk,/*synthesis PAP_MARK_DEBUG = "1"*/
    output              o_spi_rst, //也是从FPGA的复位信号
    output              o_spi_cs,/*synthesis PAP_MARK_DEBUG = "1"*/
    output              o_spi_mosi,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_spi_miso1,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_spi_miso2,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_spi_miso3,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_spi_miso4,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_spi_drdy,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_spi_err,/*synthesis PAP_MARK_DEBUG = "1"*/

    //ADS1247接口
    input               i_ads1247_drdy/*synthesis PAP_MARK_DEBUG = "1"*/, //数据转换完成
    input               i_ads1247_sdo/*synthesis PAP_MARK_DEBUG = "1"*/,  //转换数据
    output              o_ads1247_sclk/*synthesis PAP_MARK_DEBUG = "1"*/, //串行时钟
    output              o_ads1247_cs_n/*synthesis PAP_MARK_DEBUG = "1"*/, //片选信号
    output              o_ads1247_sdi/*synthesis PAP_MARK_DEBUG = "1"*/,  //数据输入
    output              o_ads1247_rst/*synthesis PAP_MARK_DEBUG = "1"*/,  //复位信号

    //FT600Q接口
    input               i_ft600_clk,/*synthesis PAP_MARK_DEBUG = "1"*/
    inout       [15:0]  io_ft600_data,/*synthesis PAP_MARK_DEBUG = "1"*/
    inout       [1:0]   io_ft600_be,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_ft600_rxf_n,/*synthesis PAP_MARK_DEBUG = "1"*/
    input               i_ft600_txe_n,/*synthesis PAP_MARK_DEBUG = "1"*/

    output              o_ft600_wr_n,/*synthesis PAP_MARK_DEBUG = "1"*/
    output              o_ft600_rd_n,/*synthesis PAP_MARK_DEBUG = "1"*/
    output              o_ft600_oe_n,/*synthesis PAP_MARK_DEBUG = "1"*/
    output              o_ft600_siwu_n,/*synthesis PAP_MARK_DEBUG = "1"*/

    output              o_ft600_rst_n,/*synthesis PAP_MARK_DEBUG = "1"*/
    output              o_ft600_wakeup,/*synthesis PAP_MARK_DEBUG = "1"*/
    inout       [1:0]   io_ft600_gpio,/*synthesis PAP_MARK_DEBUG = "1"*/

    //IO通过单板下拉接地
    input               i_signal_Gnd_0,
    input               i_signal_Gnd_1,

    //风机控制
    output              o_fan_ctl_0, //o_fan_mot_ctl[0]是Y6引脚,频率25KHz,占空比1:3
    input               o_fan_ctl_1, //o_fan_mot_ctl[1]是AA6引脚,频率200Hz,占空比50%

    //74VHCT541AFT_IC302OE使能
    output      [1:0]   o_en_74vhct541,

    //恒流源、测量电源控制信号
    output              o_power_L_pwm,       //恒流源、测量电源的开关管控制 从FPGA时钟引脚控制(200k)
    output              o_power_H_pwm,       //恒流源、测量电源的开关管控制 从FPGA复位引脚控制
    input               i_power_safety_ctl,  //恒流源、测量电源浪涌保护器模式控制
    output              o_power_safety_en    //恒流源、测量电源浪涌保护器使能
);

/***********************PLL************************/
wire            clk_100M; //主时钟
wire            clk_160M; //SPI工作时钟
wire            pll_lock;
wire            rst_n;
wire            clk_2M;   //ads1247采样时钟
reg             clk_1M;   //ads1247采样时钟
//wire          clk_50M;

//assign o_ft600_siwu_n = 1'b1;
//PLL
CLK_PLL CLK_PLL_INST (
    .clkin1     (i_clk_osc ), // input
    .pll_lock   (rst_n     ), // output
    .clkout0    (clk_100M  ), // output
    .clkout1    (clk_2M    ), // output
    .clkout2    (clk_160M  )  // output
);

//复位延时
reg     [47:0]  rst_delay_count;
reg             ADS1247_rst;       /*synthesis PAP_MARK_DEBUG = "1"*/
reg             r_host_power_rst;  /*synthesis PAP_MARK_DEBUG = "1"*/
always@(posedge clk_100M or negedge rst_n) begin
    if(!rst_n) begin
        ADS1247_rst     <= 'd0;
        rst_delay_count <= 'd0;
        r_host_power_rst <= 'd0;
    end
    else begin
        ADS1247_rst      <= ADS1247_rst;
        r_host_power_rst <= r_host_power_rst;
        rst_delay_count  <= rst_delay_count + 'd1;
        if(rst_delay_count == 2000_000)begin //PLL稳定之后在进行复位
            ADS1247_rst      <= 'd1;
            r_host_power_rst <= 'd1;
            rst_delay_count  <= rst_delay_count;
        end
    end
end

/***********************呼吸灯************************/
reg             freq_led;
reg     [31:0]  led_cnt;
always@(posedge i_clk_osc or negedge rst_n)begin
    if(!rst_n)begin
        freq_led <= 'd0;
        led_cnt  <= 'd0;
    end
    else begin
        if(led_cnt == 32'd124_999_999)begin
            freq_led <= ~freq_led;
            led_cnt  <= 'd0;
        end
        else if(led_cnt == 32'd62_499_999)begin
            freq_led <= ~freq_led;
            led_cnt  <= led_cnt + 'd1;
        end
        else
            led_cnt <= led_cnt + 'd1;
    end
end
assign  o_led1 = freq_led ? 1 : 0;
assign  o_led2 = freq_led ? 0 : 1;

/***********************TempView************************/
wire            tmp_over;
assign  tmp_over = (i_tmp302_flag) ? 0 : 1;

/***********************74VHCT541同向缓冲器使能************************/
//assign    o_en_74vhct541 = ((~i_signal_Gnd_0) && (~i_signal_Gnd_1) && rst_n) ? 2'b00 : 2'b11; //低电平有效
assign      o_en_74vhct541 = r_host_power_rst ? 2'b00 : 2'b11; //低电平有效

/***********************恒流源、测量电源控制************************/
//使能控制:从FPGA连接&&主FPGA正常工作&&从FPGA电流未报警
assign  o_power_safety_en = ((~i_signal_Gnd_0) && (~i_signal_Gnd_1) && rst_n && ~i_power_safety_ctl) ? 1'b1 : 1'b0;

/***********************风机控制************************/
//两个方波信号,o_fan_mot_ctl_1频率为200Hz,占空比50Hz
reg             freq_200hz;
reg     [18:0]  freq_200hz_cnt;
always@(posedge i_clk_osc or negedge rst_n)begin
    if(!rst_n)begin
        freq_200hz     <= 'd0;
        freq_200hz_cnt <= 'd0;
    end
    //else if((~i_signal_Gnd_0) && (~i_signal_Gnd_1)&& rst_n)begin
    else begin
        if(freq_200hz_cnt == 19'd249_999)begin
            freq_200hz     <= ~freq_200hz;
            freq_200hz_cnt <= 'd0;
        end
        else if(freq_200hz_cnt == 19'd124_999)begin
            freq_200hz     <= ~freq_200hz;
            freq_200hz_cnt <= freq_200hz_cnt + 'd1;
        end
        else
            freq_200hz_cnt <= freq_200hz_cnt + 'd1;
    end
end
//assign    o_fan_ctl_1 = r_host_power_rst ? freq_200hz : 0;

//o_fan_mot_ctl_0频率为25Khz,占空比1:3
reg             freq_25K;
reg     [10:0]  freq_25K_cnt;
always@(posedge i_clk_osc or negedge rst_n)begin
    if(!rst_n)begin
        freq_25K     <= 'd0;
        freq_25K_cnt <= 'd0;
    end
    //else if((~i_signal_Gnd_0) && (~i_signal_Gnd_1)&& rst_n)begin
    else begin
        if(freq_25K_cnt == 11'd1999)begin
            freq_25K     <= ~freq_25K;
            freq_25K_cnt <= 'd0;
        end
        else if(freq_25K_cnt == 11'd1499)begin
            freq_25K     <= ~freq_25K;
            freq_25K_cnt <= freq_25K_cnt + 'd1;
        end
        else
            freq_25K_cnt <= freq_25K_cnt + 'd1;
    end
end
assign  o_fan_ctl_0 = r_host_power_rst ? freq_25K : 0;

/***********************恒流源、测量电源的开关管控制************************/
//power_L_pwm 控制 200khz的方波
reg             freq_200K;
reg     [9:0]   freq_200K_cnt;
always@(posedge i_clk_osc or negedge rst_n)begin
    if(!rst_n)begin
        freq_200K     <= 'd0;
        freq_200K_cnt <= 'd0;
    end
    /*else if((~i_signal_Gnd_0) && (~i_signal_Gnd_1)&& rst_n)begin*/
    else begin
        if(freq_200K_cnt == 10'd249)begin
            freq_200K     <= ~freq_200K;
            freq_200K_cnt <= 'd0;
        end
        else if(freq_200K_cnt == 10'd124)begin
            freq_200K     <= ~freq_200K;
            freq_200K_cnt <= freq_200K_cnt + 'd1;
        end
        else
            freq_200K_cnt <= freq_200K_cnt + 'd1;
    end
end
assign  o_power_H_pwm = r_host_power_rst;           //延时一段时间后给高电平
assign  o_power_L_pwm = r_host_power_rst ? freq_200K : 0; //延时一段时间后,给200k时钟

/***********************ADS1247************************/
reg             ads1247_fifo_rd_clk; //ads1247fifo读取时钟
wire    [31:0]  w_ads1247_data;      //温度数据
wire    [31:0]  w_temp_data/*synthesis PAP_MARK_DEBUG = "1"*/; //温度数据
wire            clk_45k; //45.455k  实际是46.512k

CLK_DRIVER CLK_DRIVER_INST(
    .sclk     (clk_2M  ),
    .rst_n    (rst_n   ),
    .clk_out1 (clk_45k )
);

reg             ads1247_clk;
reg     [1:0]   ads1247_clk_cnt;
always@(posedge clk_2M or negedge rst_n) begin
    if(!rst_n) begin
        ads1247_clk_cnt <= 1'b0;
        ads1247_clk     <= 1'b0;
    end
    else begin
        if(ads1247_clk_cnt == 2'd1)begin
            ads1247_clk_cnt <= 'd0;
            ads1247_clk     <= ~ads1247_clk;
        end
        else
            ads1247_clk_cnt <= ads1247_clk_cnt + 'd1;
    end
end

//ADS1247驱动控制
ADS1247_DRIVE ADS1247_DRV_INST(
    .i_sys_clk          (clk_100M          ), //时钟输入 500k
    .i_sys_rst_n        (ADS1247_rst       ), //复位信号
    .i_read_clk         (clk_45k           ), //读取数据时钟
    .o_read_data        (w_ads1247_data    ), //数据输出
    .o_adc_sclk         (o_ads1247_sclk    ), //adc串行时钟输出
    .o_adc_cs_n         (o_ads1247_cs_n    ), //内阻片选
    .o_adc_sdi          (o_ads1247_sdi     ), //adc_sdi
    .i_adc_drdy         (i_ads1247_drdy    ), //转换完成
    .i_adc_sdo          (i_ads1247_sdo     ), //转换数据
    .o_adc_start        (                  ), //adc转换信号
    .o_adc_reset        (o_ads1247_rst     ), //adc转换信号
    .o_gpio_master_data (o_gpio_master_data)  //温度数据准备完成
);
reg [31:0] r_temp_data;
reg        r_gpio_master_data_d;

always @(posedge clk_100M or negedge rst_n) begin
    if(!rst_n)begin
        r_temp_data <= 32'd0;
        r_gpio_master_data_d <= 1'b0;
    end
    else begin
        r_gpio_master_data_d <= o_gpio_master_data;
        if(o_gpio_master_data && !r_gpio_master_data_d)
            r_temp_data <= w_ads1247_data;
    end
end

assign w_temp_data = r_temp_data;

/***********************通信解析************************/
wire    [2:0]   USB_state;
wire    [3:0]   o_spi_state;
wire    [4:0]   o_cmd_state;

COM_ANALYSE COM_ANALYSE_INST(
    .clk_160M           (clk_160M          ),
    .clk_100M           (clk_100M          ),
    .rst_n              (rst_n             ),

    //gpio输出
    .o_gpio_sample      (o_gpio_host_data  ),
    .o_gpio_alarm       (o_gpio_alarm      ),

    //FT600Q接口
    .i_clk_FT600        (i_ft600_clk       ),
    .io_data_FT600      (io_ft600_data     ),
    .io_byte_enable_FT600(io_ft600_be      ),
    .i_txe_n_FT600      (i_ft600_txe_n     ),
    .i_rxf_n_FT600      (i_ft600_rxf_n     ),

    .o_wr_n_FT600       (o_ft600_wr_n      ),
    .o_rd_n_FT600       (o_ft600_rd_n      ),
    .o_oe_n_FT600       (o_ft600_oe_n      ),

    .o_rst_n_FT600Q     (o_ft600_rst_n     ),
    .o_wake_n_FT600Q    (o_ft600_wakeup    ),
    .io_gpio_FT600Q     (io_ft600_gpio     ),

    //spi
    .o_spi_sclk         (o_spi_sclk        ),
    .o_spi_cs           (o_spi_cs          ),
    .o_spi_mosi         (o_spi_mosi        ),
    .o_spi_rst          (o_spi_rst         ),

    .i_spi_miso1        (i_spi_miso1       ),
    .i_spi_miso2        (i_spi_miso2       ),
    .i_spi_miso3        (i_spi_miso3       ),
    .i_spi_miso4        (i_spi_miso4       ),
    .i_spi_drdy         (i_spi_drdy        ),
    .i_spi_err          (i_spi_err         ),

    //温度数据
    .i_ads1247_data     (w_temp_data       ),

    .USB_state          (USB_state         ),
    .o_spi_state        (o_spi_state       ),
    .o_cmd_state        (o_cmd_state       )
);

endmodule
