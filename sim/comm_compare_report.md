# 通讯模块前后对比验证报告

日期: 2026-07-08

## 验证对象

- 当前工程使用 `rtl_orign` 路径下的代码，PDS 工程文件中 `SPI_DRIVE.v`、`COM_ANALYSE.v`、`MASTER_TOP.v` 均来自 `rtl_orign`。
- 本次通讯链路对比重点包含 `rtl_orign/SPI_DRIVE.v` 修改前后。
- 仿真使用工程内实际生成的 `SPI_FIFO_MISO1..4` IP RTL，并编译 Pango 仿真原语 `GTP_DRM18K.v`、`GTP_GRS.v`。
- Testbench 已加入:

```verilog
GTP_GRS GRS_INST (
    .GRS_N(1'b1)
);
```

## SPI_DRIVE 修改前后

| 项目 | 修改前 | 修改后 |
| --- | --- | --- |
| RX3/RX4 端口宽度 | `o_spi_rx_data3/4` 为 `[376:0]` | 修正为 `[367:0]`，与 FIFO 和其他 RX 端口一致 |
| SPI 内部时钟 | TX/RX 计数逻辑使用 `posedge/negedge o_spi_sclk` | 所有内部逻辑回到 `clk_160M`，用 `spi_sclk_pos/spi_sclk_neg` 作边沿使能 |
| FIFO 写时钟 | `SPI_FIFO_MISO1..4.wr_clk = o_spi_sclk` | `wr_clk = clk_160M`，避免生成时钟造成时序路径问题 |
| 启动信号 | `i_spi_tx_st` 直接进入 160M 逻辑 | 增加同步和空闲接受条件，只在 `CS` 空闲时锁存一次命令 |
| FIFO 读使能 | `rd_en = r_spi_rx_done_d0`，可能多读或过早读 | 改为单周期 `w_spi_fifo_rd_pulse` |
| RX done | `o_spi_rx_done = r_spi_rx_done_d2`，与真实 FIFO 输出不同步 | `o_spi_rx_done` 延后到 FIFO 数据有效后一拍输出 |
| 输出状态 | `o_spi_tx_done`、`o_spi_state` 原来未实际驱动，仿真为 `z` | 当前分别驱动为 `r_spi_tx_cnt_done` 和 `4'd0` |

## 其他通讯相关修改

- `rtl_orign/COM_ANALYSE.v`: 去掉 `w_spi_tx_data = r_cmd_rece_done ? r_cmd_rece_data : w_spi_tx_data` 这种自反馈写法，改为寄存 `r_spi_tx_data/r_spi_tx_st`，只在收到有效 SPI 位宽命令时发起一次 SPI 交易。
- `rtl_orign/MASTER_TOP.v`: 去掉 `w_temp_data` 自反馈，改为由 `r_temp_data` 驱动。
- `prj/project/source/pin.fdc`: 注释掉 `o_spi_sclk` 的 generated clock 约束，因为修正后 `o_spi_sclk` 不再作为内部逻辑时钟使用。

## 真实 IP 仿真结果

| 版本 | 用例 | 结果 | 关键现象 |
| --- | --- | --- | --- |
| 修改前 | `CTRL_48` | PASS | 48 bit 短返回能通过，但 FIFO 被读 2 次，`TX_DONE/STATE=z` |
| 修改前 | `RR_160` | FAIL | MOSI 正确，但 RX1/RX3 在 done 时仍是上一笔 48 bit 数据 |
| 修改前 | `ALL_368` | FAIL | 延后观察数据可对，但 done 窗口数据不对，`TX_DONE/STATE=z` |
| 修改后 | `CTRL_48` | PASS | MOSI、RX1..4、done 窗口均正确 |
| 修改后 | `RR_160` | PASS | MOSI、RX1..4、done 窗口均正确 |
| 修改后 | `ALL_368` | PASS | MOSI、RX1..4、done 窗口均正确 |

汇总:

```text
修改前: CASE=before_real_ip_simlib TOTAL_FAIL=2
修改后: CASE=after_real_ip_simlib  TOTAL_FAIL=0
```

## 可复现实验

当前版本可直接运行:

```tcl
do sim/run_spi_drive_compare_real_ip.do rtl_orign/SPI_DRIVE.v after_real_ip
```

如果需要复跑旧版，把旧版 `SPI_DRIVE.v` 路径作为第一个参数传入:

```tcl
do sim/run_spi_drive_compare_real_ip.do pic/_comm_compare/before/rtl_orign/SPI_DRIVE.v before_real_ip
```

仿真输出默认写到 `pic/_comm_compare/run/<case>_summary.txt`。`pic/` 目录已被 `.gitignore` 忽略，日志不会误提交。

## PDS 时序复查

最终 RTL 修改后已重新运行:

```powershell
D:\pango\PDS_2024.2\pango\PDS_2024.2\bin\pds_shell.exe -project E:\FPGA\ainuo\BTS7501\master\prj\project\project.pds -run report_timing
```

结果:

```text
Total Latches: 0
route_optimize: TNS = 0 ; WNS = 36 ; THS = NA ; WHS = NA
Report timing is finished successfully.
```
