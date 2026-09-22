# rtl-ip-lab —— 仿真（iverilog）与综合（yosys）
IV    ?= C:/iverilog/bin/iverilog.exe
VVP   ?= C:/iverilog/bin/vvp.exe
YOSYS_ENV ?= D:/oss-cad-suite/environment.bat
YOSYS ?= yosys
BUILD := build

TBS := tb_async_fifo tb_axis_dma tb_spi_master
RTL_tb_async_fifo := rtl/async_fifo.v
RTL_tb_axis_dma   := rtl/axis_dma.v
RTL_tb_spi_master := rtl/spi_master.v

.PHONY: all test synth clean
all: test

$(BUILD):
	@cmd /c if not exist "$(BUILD)" mkdir "$(BUILD)"

define run_tb
	@echo "########## $(1) ##########"
	@$(IV) -g2005 -o $(BUILD)/$(1).vvp $(RTL_$(1)) tb/$(1).v
	@$(VVP) $(BUILD)/$(1).vvp
endef

test: | $(BUILD)
	$(call run_tb,tb_async_fifo)
	$(call run_tb,tb_axis_dma)
	$(call run_tb,tb_spi_master)

# 综合检查：用 yosys 跑一遍综合，确认可综合并打印单元统计（对应 JD 的"代码综合"）
synth:
	@echo "########## yosys synth: async_fifo ##########"
	@cmd /c "call $(YOSYS_ENV) >nul 2>&1 && $(YOSYS) -q -p "read_verilog rtl/async_fifo.v; chparam -set DATA_WIDTH 8 -set ADDR_WIDTH 4 async_fifo; synth; stat"
	@echo "########## yosys synth: axis_dma ##########"
	@cmd /c "call $(YOSYS_ENV) >nul 2>&1 && $(YOSYS) -q -p "read_verilog rtl/axis_dma.v; chparam -set DATA_WIDTH 8 -set ADDR_WIDTH 8 -set LEN_WIDTH 8 axis_dma; synth; stat"
	@echo "########## yosys synth: spi_master ##########"
	@cmd /c "call $(YOSYS_ENV) >nul 2>&1 && $(YOSYS) -q -p "read_verilog rtl/spi_master.v; chparam -set CLK_DIV 4 -set WIDTH 8 spi_master; synth; stat"

clean:
	-@cmd /c rmdir /s /q $(BUILD)
