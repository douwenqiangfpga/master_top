// 通信指令解析状态机
`define CMD_IDLE               5'b00000    // 空闲状态

`define CMD_RD_TYPE            5'b00001    // 读取指令类型
`define CMD_RD_CTRL            5'b00010    // 读取控制指令
`define CMD_RD_SET             5'b00011    // 读取设置指令
`define CMD_RD_QUER            5'b00100    // 读取查询指令
`define CMD_RD_QUER_TEMP       5'b00101    // 查询温度指令
`define CMD_RX_SPI_TYPE        5'b00110    // 读取SPI数据类型

`define CMD_REPLY_CTRL         5'b00111    // 回复控制指令
`define CMD_REPLY_SET          5'b01000    // 回复设置指令
`define CMD_REPLY_QUER         5'b01001    // 回复查询指令
`define CMD_REPLY_TEMP         5'b01010    // 回复温度数据

`define CMD_REPLY_Length4      5'b01011    // 回复4字节指令 1、电压测试值 2、内阻原始数据 3、电压原始数据
`define CMD_REPLY_Length8      5'b01100    // 回复8字节指令 1、内阻测试值 2、线阻原始数据

`define CMD_REPLY_DATA         5'b01101    // 发送所有测试数据
`define CMD_REPLY_RR_DATA      5'b01110    // 发送线阻测试数据
`define CMD_REPLY_ALARM        5'b01111    // 发送报警

`define CMD_REPLY_VER          5'b10000    // 回复FPGA版本号指令
`define CMD_REPLY_DONE         5'b10001    // 回复完成指令
`define CMD_REPLY_ERROR        5'b10010    // 回复错误指令
`define CMD_RD_ARM_DONE        5'b10011    // 读取ARM指令完成

`define CMD_ERROR              5'b10100    // 错误状态

// FT600Q驱动状态机
`define USB_IDLE               3'b000
`define USB_TX_PRE             3'b001
`define USB_TX                 3'b010
`define USB_TX_LAST            3'b011
`define USB_OE                 3'b100
`define USB_RX_PRE             3'b101
`define USB_RX                 3'b110

// SPI驱动状态机
`define SPI_IDLE               4'b0000    // spi空闲
`define SPI_CS_EN              4'b0001    // spi片选使能
`define SPI_TX_PRE             4'b0010    // spi发送准备
`define SPI_TX                 4'b0011    // spi发送
`define SPI_RX_PRE             4'b0100    // spi接收准备
`define SPI_RX                 4'b0101    // spi接收
`define SPI_RX_LAST            4'b0110    // spi接收结束
`define SPI_STOP               4'b0111    // spi停止
`define SPI_CS_DISEN           4'b1000    // spi片选失能