module COM_DRIVER
(
    input        i_clk,
    input        i_rst_n,

    //spi时钟
    input        i_com_cs,
    input        i_com_sclk,

    //spi接收
    input        i_mosi,

    //spi发送
    output [3:0] o_miso,

    //spi 数据就绪/错误 io
    output       o_gpio_drdy,
    output       o_gpio_err /*synthesis PAP_MARK_DEBUG = "ture"*/,
    input        i_data_ready,
    input        i_clk_200M,

    //需要上传的异常
    input  [1:0] i_contact_test_alarm,
    input        i_calib_sw_err,
    input        i_adc_acr_err,
    input        i_adc_rr1_err,
    input        i_adc_rr2_err,
    input        i_adc_ocv_err,
    input        i_dac_1k_err,
    input        i_dac_6k_err,

    //需要上传的数据
    input [31:0] i_result_acr_amp,     //内阻幅值
    input [31:0] i_result_acr_angle,   //内阻角度
    input [63:0] i_h_sense_real  /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻测高实部
    input [63:0] i_h_sense_imag  /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻测高虚部
    input [63:0] i_l_sense_real  /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻测低实部
    input [63:0] i_l_sense_imag  /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻测试虚部
    input [63:0] i_h_source_real /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻源高实部
    input [63:0] i_h_source_imag /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻源高虚部
    input [63:0] i_l_source_real /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻源低实部
    input [63:0] i_l_source_imag /*synthesis PAP_MARK_DEBUG = "ture"*/, //线阻源低虚部
    input [31:0] i_result_ocv,         //电压结果
    input [23:0] i_data_acr,           //内阻ADC数据
    input [23:0] i_data_rr1,           //线阻ADC数据
    input [23:0] i_data_rr2,           //线阻ADC数据
    input [23:0] i_data_ocv,           //电压DC数据
    input [63:0] i_ocv_value,          //电压累加结果上传
    input [63:0] i_acr_1k_real,        //内阻实部累加结果上传
    input [63:0] i_acr_1k_imag,        //内阻虚部累加结果上传
    input [63:0] i_acr_incu_1k_real /*synthesis PAP_MARK_DEBUG = "ture"*/, //恒流源参考信号实部累加结果上传
    input [63:0] i_acr_incu_1k_imag /*synthesis PAP_MARK_DEBUG = "ture"*/, //恒流源参考信号虚部累加结果上传

    //下发设置/控制信息
    output reg       o_cmd_test,        //测量
    output reg       o_cmd_adj,         //调零
    output reg       o_cmd_calib_acr,   //校准，切换+采样
    output reg       o_cmd_calib_ocv,   //校准，切换+采样
    output reg       o_cmd_calib_change,//校准，切换
    output reg       o_cmd_repeat,      //重新采样
    output reg       o_cmd_stop,        //停止
    output reg       o_cmd_rdy_stop,    //数据准备停止
    output reg       o_rr_gain_sw,      //电阻校准，线路阻抗减漏保护电路通断切换
    output reg       o_acr_calib_sw,    //内阻校准信号继电器,RY300
    output reg       o_sour_ctrl_calib, //内阻校准信号继电器,RY1
    output reg [2:0] o_acr_res_sw,      //标准电阻切换
    output reg       o_cmd_calib_acr_done,//电阻校准结束
    output reg [2:0] o_ocv_calib_sw,    //电压自校准采样信号，ref, gnd, gnd
    output reg [2:0] o_cmd_func,        //档位
    output reg [4:0] o_cmd_acr_range,   //电阻量程
    output reg [2:0] o_cmd_ocv_range,   //电压量程
    output reg [3:0] o_cmd_speed,       //速度档位
    output reg [14:0] o_cmd_trig_delay, //触发延时
    output reg [1:0] o_cmd_mir,         //mir功能
    output reg       o_cmd_power,       //电源
    output reg [7:0] o_rece_cmd,
    output reg       o_change_func,     //档位修改
    output reg       o_change_acr_range,//电阻量程修改
    output reg       o_change_ocv_range,//电压量程修改
    output reg       o_change_speed,    //速度修改
    output reg       o_change_trig_delay,//触发延时修改
    output reg       o_change_mir,      //mir修改
    output reg       o_change_power     //电源修改
    ,input      [511:0] i_dbg_acr_fifo_data,
    input               i_dbg_acr_fifo_valid,
    input               i_dbg_acr_fifo_empty,
    output reg          o_dbg_acr_fifo_rd_en
);

/********** Define Parameter and Internal Signals **********/
//收发状态
localparam ST_IDEAL      = 5'd0  , //接收空闲
           ST_RECE_CMD   = 5'd1  , //接收命令
           ST_RECE_LEN   = 5'd2  , //接收数据长度
           ST_RECE_DATA  = 5'd3  , //接收数据
           ST_SEND_CMD   = 5'd4  , //发送命令
           ST_SEND_LEN   = 5'd5  , //发送数据长度
           ST_SEND_DATA0 = 5'd6  , //发送数据
           ST_SEND_DATA1 = 5'd7  , //发送数据
           ST_SEND_DATA2 = 5'd8  , //发送数据
           ST_SEND_DATA3 = 5'd9  , //发送数据
           ST_SEND_DATA4 = 5'd10 , //发送数据
           ST_SEND_DATA5 = 5'd11 , //发送数据
           ST_SEND_DATA6 = 5'd12 , //发送数据
           ST_SEND_DATA7 = 5'd13 , //发送数据
           ST_SEND_DATA8 = 5'd14 , //发送数据
           ST_SEND_DATA9 = 5'd15 , //发送数据
           ST_SEND_DATA10= 5'd16 , //发送数据
           ST_SEND_DATA11= 5'd17 , //发送数据
           ST_SEND_DATA12= 5'd18 ; //发送数据

//命令类型
localparam CMD_TYPE_CTRL = 8'h0F , // 控制指令
           CMD_TYPE_SET  = 8'h5A , // 设置指令
           CMD_TYPE_QUER = 8'hF1 , // 查询指令
           CMD_TYPE_ERR  = 8'h99 ; // 错误

//控制类命令字
localparam CMD_CTRL_TEST       = 8'h01 , //测量
           CMD_CTRL_REPEAT     = 8'h02 , //重新测量
           CMD_CTRL_STOP       = 8'h03 , //停止测量
           CMD_CTRL_ADJ        = 8'h10 , //调零
           CMD_CTRL_CALIB_ACR  = 8'h20 , //电阻校准
           CMD_CTRL_CALIB_OCV  = 8'h21 , //电压校准
           CMD_CTRL_CALIB_SW   = 8'h22 , //校准信号切换
           CMD_CTRL_CALIB_DONE = 8'h23 ; //电阻校准完成

//设置类命令字
localparam CMD_SET_FUN1     = 8'h01 , //设置量程
           CMD_SET_FUN2     = 8'h02 , //设置触发延时
           CMD_SET_FUN3     = 8'h03 , //设置MIR
           CMD_SET_GAIN_SW  = 8'h10 , //线路阻抗减漏保护电路通断切换：0-低，1-高
           CMD_SET_CALIB_SW = 8'h11 , //电阻校准继电器RY300,RY1
           CMD_SET_RES_SW   = 8'h12 ; //标准电阻控制801,802,803

//查询类命令字
localparam CMD_QUER_SN      = 8'h01 , //查询从版本号
           CMD_QUER_ERR     = 8'h02 , //查询报警信息
           CMD_QUER_ALL     = 8'h10 , //查询所有测试值
           CMD_QUER_ACR     = 8'h11 , //内阻测试值
           CMD_QUER_OCV     = 8'h12 , //电压测试值
           CMD_QUER_RR      = 8'h13 , //线阻测试值
           CMD_QUER_ADC_ACR = 8'h20 , //内阻原始数据
           CMD_QUER_ADC_RR  = 8'h21 , //线组原始数据
           CMD_QUER_ADC_OCV = 8'h22 ; //电压原始数据

//错误回传
localparam CMD_ERR_TYPE = 8'h01 , //类型错误
           CMD_ERR_LEN  = 8'h03 , //长度错误
           CMD_ERR_PARA = 8'h04 ; //参数错误

localparam PCB_VERSION   = 16'h0001, //pcb版本
           FPGA_MODEL    = 16'h0264, //fpga型号
           LOGIC_VERSION = 16'h0003, //逻辑版本号
           LOGIC_RESERVED= 16'h0000; //逻辑版本号预留

localparam COM_NULL      = 32'h0         ; //长度占空
localparam COM_ERR       = 32'hFFFFFFFF  ; //错误占空
localparam SEND_DATA_LEN = 4'h17         ; //发送数据长度

reg  [4:0]  state                 /*synthesis PAP_MARK_DEBUG = "ture"*/; //主状态
wire        rece_one_word         /*synthesis PAP_MARK_DEBUG = "ture"*/; //接收数据有效位
wire [15:0] rece_tmp              /*synthesis PAP_MARK_DEBUG = "ture"*/;
reg  [15:0] rece_tmp_d1           /*synthesis PAP_MARK_DEBUG = "ture"*/;
wire [15:0] rece_word             /*synthesis PAP_MARK_DEBUG = "ture"*/;
reg  [15:0] rece_cmd              /*synthesis PAP_MARK_DEBUG = "1"*/;    //接收命令
reg  [15:0] rece_len;                                                  //接收数据长度
reg  [15:0] rece_data;                                                 //接收数据

wire        send_one_word;                                             //发送数据有效
reg  [15:0] send_ready_1;                                              //即将发送1
reg  [15:0] send_ready_2;                                              //即将发送2
reg  [15:0] send_ready_3;                                              //即将发送3
reg  [15:0] send_ready_4         /*synthesis PAP_MARK_DEBUG = "ture"*/; //即将发送4

reg  [15:0] send_cmd;                                                  //发送指令
reg  [15:0] send_len;                                                  //发送数据长度
reg  [15:0] send_data1 [12:0];                                         //查询指令回传数据，每次通过o_data_x发送两字节
reg  [15:0] send_data2 [12:0];                                         //查询指令回传数据，每次通过o_data_x发送两字节
reg  [15:0] send_data3 [12:0];                                         //查询指令回传数据，每次通过o_data_x发送两字节
reg  [15:0] send_data4 [12:0];                                         //查询指令回传数据，每次通过o_data_x发送两字节

reg  [15:0] cmd_set1;      //指令设置1
reg  [15:0] cmd_set2;      //指令设置2
reg  [15:0] cmd_set3;      //指令设置3
reg  [15:0] cmd_ctrl;      //指令控制
reg         r_send_data_vaild;
reg         i_cmd_quer_all        /*synthesis PAP_MARK_DEBUG = "ture"*/;
localparam CMD_QUER_ACR_FIFO = 8'h23;
reg  [511:0] r_dbg_acr_fifo_data;
reg          r_dbg_acr_fifo_data_valid;

//error
wire [15:0] w_error /*synthesis PAP_MARK_DEBUG = "ture"*/;
assign w_error[1:0] = i_contact_test_alarm;
assign w_error[2]   = i_adc_acr_err;
assign w_error[3]   = i_adc_rr1_err;
assign w_error[4]   = i_adc_rr2_err;
assign w_error[5]   = i_adc_ocv_err;
assign w_error[6]   = i_calib_sw_err;
assign w_error[7]   = i_dac_1k_err;
assign w_error[8]   = i_dac_6k_err;

assign o_rece_cmd = rece_cmd[15:8];
assign rece_word = rece_tmp_d1;

always @(posedge i_clk or posedge i_com_cs) begin
    if (i_com_cs)
        rece_tmp_d1 <= 16'd0;
    else
        rece_tmp_d1 <= rece_tmp;
end

/*********************** Main Code ************************/
always @(posedge i_clk) begin
    if (i_com_cs) begin //数据有效使能信号
        state <= ST_RECE_CMD;
    end else begin
        if (rece_one_word) begin
            case (state)
                ST_RECE_CMD : state <= ST_RECE_LEN;
                ST_RECE_LEN : state <= ST_RECE_DATA;
                ST_RECE_DATA: state <= ST_SEND_CMD;
                ST_SEND_CMD : state <= ST_SEND_LEN;
                ST_SEND_LEN : state <= ST_SEND_DATA0;

                ST_SEND_DATA0: begin
                    if (rece_cmd[15:8] == CMD_TYPE_QUER) begin
                        state <= ST_SEND_DATA1;
                    end else begin
                        state <= ST_IDEAL;
                    end
                end

                ST_SEND_DATA1: begin
                    if (rece_cmd[7:0] == CMD_QUER_ALL || rece_cmd[7:0] == CMD_QUER_RR || rece_cmd[7:0] == CMD_QUER_ACR_FIFO) begin
                        state <= ST_SEND_DATA2;
                    end else begin
                        state <= ST_IDEAL;
                    end
                end

                ST_SEND_DATA2 : state <= ST_SEND_DATA3;
                ST_SEND_DATA3 : state <= ST_SEND_DATA4;
                ST_SEND_DATA4 : state <= ST_SEND_DATA5;
                ST_SEND_DATA5 : state <= ST_SEND_DATA6;
                ST_SEND_DATA6 : state <= ST_SEND_DATA7;

                ST_SEND_DATA7: begin
                    if (rece_cmd[7:0] == CMD_QUER_ALL) begin
                        state <= ST_SEND_DATA8;
                    end else begin
                        state <= ST_IDEAL;
                    end
                end

                ST_SEND_DATA8  : state <= ST_SEND_DATA9;
                ST_SEND_DATA9  : state <= ST_SEND_DATA10;
                ST_SEND_DATA10 : state <= ST_SEND_DATA11;
                ST_SEND_DATA11 : state <= ST_SEND_DATA12;
                ST_SEND_DATA12 : state <= ST_IDEAL;

                default: state <= ST_IDEAL;
            endcase
        end else begin
            state <= state;
        end
    end
end

//接收(命令、数据长度、数据)
always @(posedge i_clk or posedge i_com_cs) begin
//always @(posedge i_clk ) begin
    if (i_com_cs) begin
        rece_cmd  <= 'b0;
        rece_len  <= 'b0;
        rece_data <= 'b0;
    end else begin
        //rece_one_word 为高电平，rece_tmp 已更新 state 未更新，此时赋值会将下一个值覆盖当前值
        if (rece_one_word) begin
            case (state)
                ST_RECE_CMD : rece_cmd  <= rece_tmp;
                ST_RECE_LEN : rece_len  <= rece_tmp;
                ST_RECE_DATA: rece_data <= rece_tmp;
            endcase
        end
    end
end

//发送
//send_ready_1
always @(posedge i_clk or posedge i_com_cs) begin
    if (i_com_cs) begin
        send_ready_1     <= 'b0;
        send_ready_2     <= 'b0;
        send_ready_3     <= 'b0;
        send_ready_4     <= 'b0;
        r_send_data_vaild<= 'b0;
    end else begin
        if (rece_one_word) begin
            case (state)
                ST_SEND_CMD: begin
                    send_ready_1 <= send_cmd;
                    send_ready_2 <= send_cmd;
                    send_ready_3 <= send_cmd;
                    send_ready_4 <= send_cmd;
                    r_send_data_vaild <= 1;
                end

                ST_SEND_LEN: begin
                    send_ready_1 <= send_len;
                    send_ready_2 <= send_len;
                    send_ready_3 <= send_len;
                    send_ready_4 <= send_len;
                end

                ST_SEND_DATA0: begin
                    send_ready_1 <= send_data1[0];
                    send_ready_2 <= send_data2[0];
                    send_ready_3 <= send_data3[0];
                    send_ready_4 <= send_data4[0];
                end

                ST_SEND_DATA1: begin
                    send_ready_1 <= send_data1[1];
                    send_ready_2 <= send_data2[1];
                    send_ready_3 <= send_data3[1];
                    send_ready_4 <= send_data4[1];
                end

                ST_SEND_DATA2: begin
                    send_ready_1 <= send_data1[2];
                    send_ready_2 <= send_data2[2];
                    send_ready_3 <= send_data3[2];
                    send_ready_4 <= send_data4[2];
                end

                ST_SEND_DATA3: begin
                    send_ready_1 <= send_data1[3];
                    send_ready_2 <= send_data2[3];
                    send_ready_3 <= send_data3[3];
                    send_ready_4 <= send_data4[3];
                end

                ST_SEND_DATA4: begin
                    send_ready_1 <= send_data1[4];
                    send_ready_2 <= send_data2[4];
                    send_ready_3 <= send_data3[4];
                    send_ready_4 <= send_data4[4];
                end

                ST_SEND_DATA5: begin
                    send_ready_1 <= send_data1[5];
                    send_ready_2 <= send_data2[5];
                    send_ready_3 <= send_data3[5];
                    send_ready_4 <= send_data4[5];
                end

                ST_SEND_DATA6: begin
                    send_ready_1 <= send_data1[6];
                    send_ready_2 <= send_data2[6];
                    send_ready_3 <= send_data3[6];
                    send_ready_4 <= send_data4[6];
                end

                ST_SEND_DATA7: begin
                    send_ready_1 <= send_data1[7];
                    send_ready_2 <= send_data2[7];
                    send_ready_3 <= send_data3[7];
                    send_ready_4 <= send_data4[7];
                end

                ST_SEND_DATA8: begin
                    send_ready_1 <= send_data1[8];
                    send_ready_2 <= send_data2[8];
                    send_ready_3 <= send_data3[8];
                    send_ready_4 <= send_data4[8];
                end

                ST_SEND_DATA9: begin
                    send_ready_1 <= send_data1[9];
                    send_ready_2 <= send_data2[9];
                    send_ready_3 <= send_data3[9];
                    send_ready_4 <= send_data4[9];
                end

                ST_SEND_DATA10: begin
                    send_ready_1 <= send_data1[10];
                    send_ready_2 <= send_data2[10];
                    send_ready_3 <= send_data3[10];
                    send_ready_4 <= send_data4[10];
                end

                ST_SEND_DATA11: begin
                    send_ready_1 <= send_data1[11];
                    send_ready_2 <= send_data2[11];
                    send_ready_3 <= send_data3[11];
                    send_ready_4 <= send_data4[11];
                end

                ST_SEND_DATA12: begin
                    send_ready_1 <= send_data1[12];
                    send_ready_2 <= send_data2[12];
                    send_ready_3 <= send_data3[12];
                    send_ready_4 <= send_data4[12];
                end

                default: begin
                    send_ready_1 <= 'b0;
                    send_ready_2 <= 'b0;
                    send_ready_3 <= 'b0;
                    send_ready_4 <= 'b0;
                end
            endcase
        end
    end
end

always @(posedge i_clk or posedge i_com_cs) begin
    if (i_com_cs) begin
        o_dbg_acr_fifo_rd_en <= 1'b0;
        r_dbg_acr_fifo_data <= 512'b0;
        r_dbg_acr_fifo_data_valid <= 1'b0;
    end else begin
        o_dbg_acr_fifo_rd_en <= 1'b0;

        if (rece_one_word && state == ST_RECE_CMD && rece_tmp == {CMD_TYPE_QUER, CMD_QUER_ACR_FIFO}) begin
            r_dbg_acr_fifo_data <= 512'b0;
            r_dbg_acr_fifo_data_valid <= 1'b0;
            if (!i_dbg_acr_fifo_empty)
                o_dbg_acr_fifo_rd_en <= 1'b1;
        end

        if (i_dbg_acr_fifo_valid) begin
            r_dbg_acr_fifo_data <= i_dbg_acr_fifo_data;
            r_dbg_acr_fifo_data_valid <= 1'b1;
        end
    end
end

integer i;
always @(posedge i_clk or posedge i_com_cs) begin
//always @(posedge i_clk ) begin
    if (i_com_cs) begin
        send_cmd <= 0;
        send_len <= 0;
        i_cmd_quer_all <= 0;
        for (i = 0; i < SEND_DATA_LEN; i = i + 1) begin
            send_data1[i] <= 0;
            send_data2[i] <= 0;
            send_data3[i] <= 0;
            send_data4[i] <= 0;
        end
    end else begin
        if (rece_one_word) begin
            case (state)
                ST_RECE_CMD: begin //接收指令
                    case (rece_tmp)
                        //控制
                        {CMD_TYPE_CTRL, CMD_CTRL_TEST       }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_REPEAT     }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_STOP       }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_ADJ        }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_CALIB_ACR  }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_CALIB_DONE }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_CALIB_OCV  }: send_cmd <= rece_tmp;
                        {CMD_TYPE_CTRL, CMD_CTRL_CALIB_SW   }: send_cmd <= rece_tmp;

                        //设置
                        {CMD_TYPE_SET , CMD_SET_FUN1     }: send_cmd <= rece_tmp; //设置量程
                        {CMD_TYPE_SET , CMD_SET_FUN2     }: send_cmd <= rece_tmp; //设置触发延时
                        {CMD_TYPE_SET , CMD_SET_FUN3     }: send_cmd <= rece_tmp; //设置MIR
                        {CMD_TYPE_SET , CMD_SET_GAIN_SW  }: send_cmd <= rece_tmp; //设置线路阻抗减漏保护电路通断切换
                        {CMD_TYPE_SET , CMD_SET_CALIB_SW }: send_cmd <= rece_tmp; //设置内阻校准信号继电器
                        {CMD_TYPE_SET , CMD_SET_RES_SW   }: send_cmd <= rece_tmp; //设置标准电阻切换

                        //查询
                        {CMD_TYPE_QUER, CMD_QUER_SN      }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_ERR     }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_ALL     }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_ACR     }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_OCV     }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_RR      }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_ADC_ACR }: send_cmd <= rece_tmp;
                        {CMD_TYPE_QUER, CMD_QUER_ACR_FIFO}: send_cmd <= rece_tmp;

                        default: send_cmd <= {CMD_TYPE_ERR, CMD_ERR_TYPE};
                    endcase
                end

                ST_RECE_LEN: begin //接收数据长度，ST_RECE_LEN = 4'h2
                    if (send_cmd == {CMD_TYPE_ERR, CMD_ERR_TYPE}) begin //命令错误
                    //if (send_cmd == {11, 11}) begin //命令错误
                        send_len <= 'd2;
                    end else begin
                        if (rece_tmp == 2) begin //正确
                            casex (rece_cmd)
                                //控制
                                {CMD_TYPE_CTRL, 8'hxx}: send_len <= 'd2;

                                //设置
                                {CMD_TYPE_SET , 8'hxx}: send_len <= 'd2;

                                //查询
                                {CMD_TYPE_QUER, CMD_QUER_SN     }: send_len <= 'd8  ;
                                {CMD_TYPE_QUER, CMD_QUER_ERR    }: send_len <= 'd2  ;
                                {CMD_TYPE_QUER, CMD_QUER_ALL    }: send_len <= 'd104;
                                {CMD_TYPE_QUER, CMD_QUER_ACR    }: send_len <= 'd16 ;
                                {CMD_TYPE_QUER, CMD_QUER_OCV    }: send_len <= 'd8  ;
                                {CMD_TYPE_QUER, CMD_QUER_RR     }: send_len <= 'd64 ;
                                {CMD_TYPE_QUER, CMD_QUER_ADC_ACR}: send_len <= 'd16 ;
                                {CMD_TYPE_QUER, CMD_QUER_ACR_FIFO}: send_len <= 'd64 ;

                                default: send_len <= 3;
                            endcase
                        end else begin //长度错误
                            send_cmd <= {CMD_TYPE_ERR, CMD_ERR_LEN};
                            send_len <= 'd2;
                        end
                    end
                end

                ST_RECE_DATA: begin //接收数据
                    casex (rece_cmd)
                        //控制
                        {CMD_TYPE_CTRL, 8'hxx}: send_data1[0] <= rece_tmp;

                        //设置
                        {CMD_TYPE_SET , 8'hxx}: send_data1[0] <= rece_tmp;

                        //查询
                        {CMD_TYPE_QUER, CMD_QUER_SN}: begin //{查询命令，查询从版本号}
                            send_data1[0] <= PCB_VERSION;
                            send_data2[0] <= FPGA_MODEL;
                            send_data3[0] <= LOGIC_VERSION;
                            send_data4[0] <= LOGIC_RESERVED;
                        end

                        {CMD_TYPE_QUER, CMD_QUER_ERR}: //{查询命令，查询错误}
                            send_data1[0] <= w_error;

                        {CMD_TYPE_QUER, CMD_QUER_ALL}: begin //{查询命令，查询所有信息}
                            i_cmd_quer_all <= 1;
                            {send_data1[0], send_data2[0]} <= i_acr_1k_real[63:32]; //内阻幅值
                            {send_data3[0], send_data4[0]} <= i_acr_1k_real[31:0];

                            {send_data1[1], send_data2[1]} <= i_acr_1k_imag[63:32]; //内阻角度
                            {send_data3[1], send_data4[1]} <= i_acr_1k_imag[31:0];

                            {send_data1[2], send_data2[2]} <= i_acr_incu_1k_real[63:32]; //恒流源参考信号实部
                            {send_data3[2], send_data4[2]} <= i_acr_incu_1k_real[31:0];

                            {send_data1[3], send_data2[3]} <= i_acr_incu_1k_imag[63:32]; //恒流源参考信号虚部
                            {send_data3[3], send_data4[3]} <= i_acr_incu_1k_imag[31:0];

                            {send_data1[4], send_data2[4]} <= i_ocv_value[63:32]; //电压结果
                            {send_data3[4], send_data4[4]} <= i_ocv_value[31:0];

                            {send_data1[5], send_data2[5]} <= i_h_source_real[63:32]; //线阻H_Soure_Real[63:32]
                            {send_data3[5], send_data4[5]} <= i_h_source_real[31:0];  //线阻H_Soure_Real[31:0]

                            {send_data1[6], send_data2[6]} <= i_h_source_imag[63:32]; //线阻H_Soure_Imag[63:32]
                            {send_data3[6], send_data4[6]} <= i_h_source_imag[31:0];  //线阻H_Soure_Imag[31:0]

                            {send_data1[7], send_data2[7]} <= i_l_source_real[63:32]; //线阻L_Soure_Real[63:32]
                            {send_data3[7], send_data4[7]} <= i_l_source_real[31:0];  //线阻L_Soure_Real[31:0]

                            {send_data1[8], send_data2[8]} <= i_l_source_imag[63:32]; //线阻L_Soure_Imag[63:32]
                            {send_data3[8], send_data4[8]} <= i_l_source_imag[31:0];  //线阻L_Soure_Imag[31:0]

                            {send_data1[9], send_data2[9]}   <= i_h_sense_real[63:32]; //线阻H_Sense_Real[63:32]
                            {send_data3[9], send_data4[9]}   <= i_h_sense_real[31:0];  //线阻H_Sense_Real[31:0]

                            {send_data1[10], send_data2[10]} <= i_h_sense_imag[63:32]; //线阻H_Sense_Imag[63:32]
                            {send_data3[10], send_data4[10]} <= i_h_sense_imag[31:0];  //线阻H_Sense_Imag[31:0]

                            {send_data1[11], send_data2[11]} <= i_l_sense_real[63:32]; //线阻L_Sense_Real[63:32]
                            {send_data3[11], send_data4[11]} <= i_l_sense_real[31:0];  //线阻L_Sense_Real[31:0]

                            {send_data1[12], send_data2[12]} <= i_l_sense_imag[63:32]; //线阻L_Sense_Real[63:32]
                            {send_data3[12], send_data4[12]} <= i_l_sense_imag[31:0];  //线阻L_Sense_Real[31:0]
                        end

                        {CMD_TYPE_QUER, CMD_QUER_ACR}: begin
                            {send_data1[0], send_data2[0]} <= i_acr_1k_real[63:32]; //内阻幅值
                            {send_data3[0], send_data4[0]} <= i_acr_1k_real[31:0];

                            {send_data1[1], send_data2[1]} <= i_acr_1k_imag[63:32]; //内阻角度
                            {send_data3[1], send_data4[1]} <= i_acr_1k_imag[31:0];
                        end

                        {CMD_TYPE_QUER, CMD_QUER_OCV}: begin
                            {send_data1[0], send_data2[0]} <= i_ocv_value[63:32]; //电压结果
                            {send_data3[0], send_data4[0]} <= i_ocv_value[31:0];
                        end

                        {CMD_TYPE_QUER, CMD_QUER_RR}: begin
                            {send_data1[0], send_data2[0]} <= i_h_source_real[63:32]; //线阻H_Soure_Real[63:32]
                            {send_data3[0], send_data4[0]} <= i_h_source_real[31:0];  //线阻H_Soure_Real[31:0]

                            {send_data1[1], send_data2[1]} <= i_h_source_imag[63:32]; //线阻H_Soure_Imag[63:32]
                            {send_data3[1], send_data4[1]} <= i_h_source_imag[31:0];  //线阻H_Soure_Imag[31:0]

                            {send_data1[2], send_data2[2]} <= i_l_source_real[63:32]; //线阻L_Soure_Real[63:32]
                            {send_data3[2], send_data4[2]} <= i_l_source_real[31:0];  //线阻L_Soure_Real[31:0]

                            {send_data1[3], send_data2[3]} <= i_l_source_imag[63:32]; //线阻L_Soure_Imag[63:32]
                            {send_data3[3], send_data4[3]} <= i_l_source_imag[31:0];  //线阻L_Soure_Imag[31:0]

                            {send_data1[4], send_data2[4]} <= i_h_sense_real[63:32]; //线阻H_Sense_Real[63:32]
                            {send_data3[4], send_data4[4]} <= i_h_sense_real[31:0];  //线阻H_Sense_Real[31:0]

                            {send_data1[5], send_data2[5]} <= i_h_sense_imag[63:32]; //线阻H_Sense_Imag[63:32]
                            {send_data3[5], send_data4[5]} <= i_h_sense_imag[31:0];  //线阻H_Sense_Imag[31:0]

                            {send_data1[6], send_data2[6]} <= i_l_sense_real[63:32]; //线阻L_Sense_Real[63:32]
                            {send_data3[6], send_data4[6]} <= i_l_sense_real[31:0];  //线阻L_Sense_Real[31:0]

                            {send_data1[7], send_data2[7]} <= i_l_sense_imag[63:32]; //线阻L_Sense_Real[63:32]
                            {send_data3[7], send_data4[7]} <= i_l_sense_imag[31:0];  //线阻L_Sense_Real[31:0]
                        end

                        {CMD_TYPE_QUER, CMD_QUER_ADC_ACR}: begin
                            {send_data1[0], send_data2[0]} <= i_data_acr; //内阻ADC数据
                            {send_data3[0], send_data4[0]} <= i_data_ocv; //电压DC数据

                            {send_data1[1], send_data2[1]} <= i_data_rr1; //线阻1ADC数据
                            {send_data3[1], send_data4[1]} <= i_data_rr2; //线阻1ADC数据
                        end

                        {CMD_TYPE_QUER, CMD_QUER_ACR_FIFO}: begin
                            {send_data1[0], send_data2[0]} <= r_dbg_acr_fifo_data[511:480];
                            {send_data3[0], send_data4[0]} <= r_dbg_acr_fifo_data[479:448];

                            {send_data1[1], send_data2[1]} <= r_dbg_acr_fifo_data[447:416];
                            {send_data3[1], send_data4[1]} <= r_dbg_acr_fifo_data[415:384];

                            {send_data1[2], send_data2[2]} <= r_dbg_acr_fifo_data[383:352];
                            {send_data3[2], send_data4[2]} <= r_dbg_acr_fifo_data[351:320];

                            {send_data1[3], send_data2[3]} <= r_dbg_acr_fifo_data[319:288];
                            {send_data3[3], send_data4[3]} <= r_dbg_acr_fifo_data[287:256];

                            {send_data1[4], send_data2[4]} <= r_dbg_acr_fifo_data[255:224];
                            {send_data3[4], send_data4[4]} <= r_dbg_acr_fifo_data[223:192];

                            {send_data1[5], send_data2[5]} <= r_dbg_acr_fifo_data[191:160];
                            {send_data3[5], send_data4[5]} <= r_dbg_acr_fifo_data[159:128];

                            {send_data1[6], send_data2[6]} <= r_dbg_acr_fifo_data[127:96];
                            {send_data3[6], send_data4[6]} <= r_dbg_acr_fifo_data[95:64];

                            {send_data1[7], send_data2[7]} <= r_dbg_acr_fifo_data[63:32];
                            {send_data3[7], send_data4[7]} <= r_dbg_acr_fifo_data[31:0];
                        end

                        default: begin
                            for (i = 0; i < SEND_DATA_LEN; i = i + 1) begin
                                send_data1[i] <= 0;
                                send_data2[i] <= 0;
                                send_data3[i] <= 0;
                                send_data4[i] <= 0;
                            end
                            i_cmd_quer_all <= 0;
                        end
                    endcase
                end
            endcase
        end
    end
end

// o_cmd_rdy_stop
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        o_cmd_rdy_stop <= 0;
    else if (rece_cmd == {CMD_TYPE_QUER, CMD_QUER_ALL})
        o_cmd_rdy_stop <= 1;
    else
        o_cmd_rdy_stop <= 0;
end

//控制/设置状态
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        cmd_set1         <= 16'h6120; //设置初始值：20110 0001 0010 0000? = 功能：03-ov,内阻量程：2-300mΩ,电压量程：2-10V HIGH-Z,采样速度：0-SLOW2
        cmd_set2         <= 'b0;
        cmd_set3         <= 'b0;
        cmd_ctrl         <= 'b0;
        o_rr_gain_sw     <= 0;
        o_acr_calib_sw   <= 1;
        o_sour_ctrl_calib<= 1;
        o_acr_res_sw     <= 3'b000;
    end else begin
        if (state == ST_SEND_CMD) begin
            case (rece_cmd[15:8])
                CMD_TYPE_CTRL: cmd_ctrl <= rece_cmd[7:0]; //控制指令
                CMD_TYPE_SET : begin //设置指令
                    case (rece_cmd[7:0])
                        CMD_SET_FUN1   : cmd_set1 <= rece_data; //设置量程
                        CMD_SET_FUN2   : cmd_set2 <= rece_data; //设置触发延时
                        CMD_SET_FUN3   : cmd_set3 <= rece_data; //设置MIR
                        CMD_SET_GAIN_SW: o_rr_gain_sw <= rece_data[0]; //线路阻抗减漏保护电路通断切换
                        CMD_SET_CALIB_SW: begin
                            o_acr_calib_sw    <= rece_data[0]; //内阻校准信号继电器,RY300
                            o_sour_ctrl_calib <= rece_data[0]; //内阻校准信号继电器,RY1
                        end
                        CMD_SET_RES_SW : o_acr_res_sw <= rece_data[2:0]; //校准切换
                    endcase
                end
            endcase
        end else begin
            cmd_set1          <= cmd_set1;
            cmd_set2          <= cmd_set2;
            cmd_set3          <= cmd_set3;
            cmd_ctrl          <= cmd_ctrl;
            o_rr_gain_sw      <= o_rr_gain_sw;
            o_acr_calib_sw    <= o_acr_calib_sw;
            o_sour_ctrl_calib <= o_sour_ctrl_calib;
            o_acr_res_sw      <= o_acr_res_sw;
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_cmd_test        <= 0;
        o_cmd_adj         <= 0;
        o_cmd_calib_acr   <= 0;
        o_cmd_calib_ocv   <= 0;
        o_cmd_calib_change<= 0;
        o_cmd_calib_acr_done <= 0;
        o_cmd_repeat      <= 0;
        o_cmd_stop        <= 0;
    end else begin
        o_cmd_test        <= 0;
        o_cmd_adj         <= 0;
        o_cmd_calib_acr   <= 0;
        o_cmd_calib_ocv   <= 0;
        o_cmd_calib_change<= 0;
        o_cmd_calib_acr_done <= 0;
        o_cmd_repeat      <= 0;
        o_cmd_stop        <= 0;
        //等待指令接收完成在进行解析处理
        if (state == ST_SEND_CMD && rece_cmd[15:8] == CMD_TYPE_CTRL) begin
            case (rece_cmd[7:0])
                CMD_CTRL_TEST      : o_cmd_test         <= 1;
                CMD_CTRL_ADJ       : o_cmd_adj          <= 1;
                CMD_CTRL_CALIB_ACR : o_cmd_calib_acr    <= 1;
                CMD_CTRL_CALIB_OCV : o_cmd_calib_ocv    <= 1;
                CMD_CTRL_CALIB_SW  : o_cmd_calib_change <= 1;
                CMD_CTRL_CALIB_DONE: o_cmd_calib_acr_done <= 1;
                CMD_CTRL_REPEAT    : o_cmd_repeat       <= 1;
                CMD_CTRL_STOP      : o_cmd_stop         <= 1;
                default: begin
                    o_cmd_test         <= 0;
                    o_cmd_adj          <= 0;
                    o_cmd_calib_acr    <= 0;
                    o_cmd_calib_ocv    <= 0;
                    o_cmd_calib_change <= 0;
                    o_cmd_calib_acr_done <= 0;
                    o_cmd_repeat       <= 0;
                    o_cmd_stop         <= 0;
                end
            endcase
        end
    end
end

//电压校准，校准切换
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_ocv_calib_sw <= 0;
    end else begin
        //等待指令接收完成在进行解析处理
        if (state == ST_SEND_CMD && rece_cmd[15:8] == CMD_TYPE_CTRL) begin
            case (rece_cmd[7:0])
                CMD_CTRL_CALIB_OCV: o_ocv_calib_sw <= rece_data; //电压校准
                CMD_CTRL_CALIB_SW : o_ocv_calib_sw <= rece_data; //校准切换
                default: o_ocv_calib_sw <= o_ocv_calib_sw;
            endcase
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        // cmd_set1_back <= 0;
        o_change_func      <= 0;
        o_change_acr_range <= 0;
        o_change_ocv_range <= 0;
        o_change_speed     <= 0;
        o_cmd_func         <= 0;
        o_cmd_acr_range    <= 0;
        o_cmd_ocv_range    <= 0;
        o_cmd_speed        <= 0;
    end else begin
        //设置功能
        if (cmd_set1[15:13] == o_cmd_func) begin
            o_change_func <= 0;
            o_cmd_func    <= o_cmd_func;
        end else begin
            o_change_func <= 1;
            o_cmd_func    <= cmd_set1[15:13];
        end

        //设置内阻量程
        if (cmd_set1[11:7] == o_cmd_acr_range) begin
            o_change_acr_range <= 0;
            o_cmd_acr_range    <= o_cmd_acr_range;
        end else begin
            o_change_acr_range <= 1;
            o_cmd_acr_range    <= cmd_set1[11:7];
        end

        //设置电压量程
        if (cmd_set1[6:4] == o_cmd_ocv_range) begin
            o_change_ocv_range <= 0;
            o_cmd_ocv_range    <= o_cmd_ocv_range;
        end else begin
            o_change_ocv_range <= 1;
            o_cmd_ocv_range    <= cmd_set1[6:4];
        end

        //设置采样周期
        if (cmd_set1[3:0] == o_cmd_speed) begin
            o_change_speed <= 0;
            o_cmd_speed    <= o_cmd_speed;
        end else begin
            o_change_speed <= 1;
            o_cmd_speed    <= cmd_set1[3:0];
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_change_trig_delay <= 0;
        o_cmd_trig_delay    <= 0;
    end else begin
        //设置触发延时
        if (cmd_set2[14:0] == o_cmd_trig_delay) begin
            o_change_trig_delay <= 0;
            o_cmd_trig_delay    <= o_cmd_trig_delay;
        end else begin
            o_change_trig_delay <= 1;
            o_cmd_trig_delay    <= cmd_set2[14:0];
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        // cmd_set3_back <= 0;
        o_change_mir   <= 0;
        o_change_power <= 0;
        o_cmd_mir      <= 0;
        o_cmd_power    <= 0;
    end else begin
        //设置MIR模式
        if (cmd_set3[11:10] == o_cmd_mir) begin
            o_change_mir <= 0;
            o_cmd_mir    <= o_cmd_mir;
        end else begin
            o_change_mir <= 1;
            o_cmd_mir    <= cmd_set3[11:10];
        end

        //设置供电频率
        if (cmd_set3[7] == o_cmd_power) begin
            o_change_power <= 0;
            o_cmd_power    <= o_cmd_power;
        end else begin
            o_change_power <= 1;
            o_cmd_power    <= cmd_set3[7];
        end
    end
end

/* gpio_drdy 在计算完成时，置高；上位机查询数据后，清零 */
reg gpio_drdy;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        gpio_drdy <= 0;
    end else begin
        if (i_data_ready) begin
            gpio_drdy <= 1;
        end else if (rece_cmd == {CMD_TYPE_QUER, CMD_QUER_ALL}) begin //在收到o_gpio_drdy=1后，上位机发送固定指令0xF110
            gpio_drdy <= 0;
        end
    end
end
assign o_gpio_drdy = gpio_drdy;

reg [23:0] gpio_drdy_cnt /*synthesis PAP_MARK_DEBUG = "1"*/;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        gpio_drdy_cnt <= 0;
    else if (gpio_drdy)
        gpio_drdy_cnt <= gpio_drdy_cnt + 1;
    else
        gpio_drdy_cnt <= 0;
end

/* gpio_err 在错误状态改变时，置高；上位机查询错误状态后，清零 */
//reg [15:0] err_back;
reg        r_gpio_err /*synthesis PAP_MARK_DEBUG = "1"*/;
reg [19:0] r_err_count /*synthesis PAP_MARK_DEBUG = "1"*/;
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_gpio_err  <= 0;
        r_err_count <= 0;
    end else begin
        if (w_error != 'd0) begin
            r_err_count <= r_err_count + 1;
            if (r_err_count >= 399_999)
                r_gpio_err <= 1;
            // casex (rece_cmd)
            // {CMD_TYPE_QUER, 8'hxx}: send_len <= 'd8;
        end else if (w_error == 'd0) begin
            r_gpio_err  <= 0;
            r_err_count <= 0;
        end
    end
end
assign o_gpio_err = r_gpio_err;

/*********************** Instance ************************/
COM_RECEIVE COM_RECEIVE_INST
(
    .i_clk         ( i_clk       ),
    .i_rst_n       ( ~i_com_cs   ),
    .i_clk_200M    ( i_clk_200M  ),
    .i_com_sclk    ( i_com_sclk  ),
    .i_mosi        ( i_mosi      ),
    .o_rece_data   ( rece_tmp    ),
    .o_rece_one_word( rece_one_word )
);

COM_SEND COM_SEND_INST
(
    .i_clk         ( i_clk          ),
    .i_rst_n       ( ~i_com_cs      ),
    .i_com_sclk    ( i_com_sclk     ),
    .i_send_data_1 ( send_ready_1   ),
    .i_send_data_2 ( send_ready_2   ),
    .i_send_data_3 ( send_ready_3   ),
    .i_send_data_4 ( send_ready_4   ),
    .i_data_valid  ( r_send_data_vaild ),
    .o_miso        ( o_miso         ),
    .o_send_one_word( send_one_word )
);

endmodule
