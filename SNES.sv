//============================================================================
//  SNES for MiSTer
//  Copyright (C) 2017-2019 Srg320
//  Copyright (C) 2018-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================ 

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[20:19];

assign LED_USER  = cart_download | (status[23] & bk_pending);
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

assign VIDEO_ARX = status[31:30] == 2 ? 8'd16 : (status[30] ? 8'd8 : 8'd64);
assign VIDEO_ARY = status[31:30] == 2 ? 8'd9  : (status[30] ? 8'd7 : 8'd49);

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire clock_locked;
wire clk_mem;
wire clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_mem),
	.outclk_1(SDRAM_CLK),
	.outclk_2(CLK_VIDEO),
	.outclk_3(clk_sys),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(clock_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg pald = 0, pald2 = 0;
	reg [2:0] state = 0;

	pald  <= PAL;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 != pald) state <= 1;

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			3: begin
					cfg_address <= 7;
					cfg_data <= pald2 ? 2201376898 : 2537930535;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire reset = RESET | buttons[1] | status[0] | cart_download | bk_loading;

////////////////////////////  HPS I/O  //////////////////////////////////

`include "build_id.v"
parameter CONF_STR = {
    "SNES;;",
    "FS,SFCSMCBIN;",
    "-;",
    "OEF,Video Region,Auto,NTSC,PAL;",
    "O13,ROM Header,Auto,No Header,LoROM,HiROM,ExHiROM;",
    "-;",
    "C,Cheats;",
    "H2OO,Cheats Enabled,Yes,No;",
    "-;",
    "D0RC,Load Backup RAM;",
    "D0RD,Save Backup RAM;",
    "D0ON,Autosave,Off,On;",
    "D0-;",
    "OUV,Aspect Ratio,4:3,8:7,16:9;",
    "O9B,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
    "OG,Pseudo Transparency,Blend,Off;",
    "OJK,Stereo Mix,None,25%,50%,100%;", 
    "-;",
    "O56,Mouse,None,Port1,Port2;",
    "O7,Swap Joysticks,No,Yes;",
    "OH,Multitap,Disabled,Port2;",
    "O8,Serial,OFF,SNAC;",
    "-;",
    "OPQ,Super Scope,Disabled,Joy1,Joy2,Mouse;",
    "D4OR,Super Scope Btn,Joy,Mouse;",
    "D4OST,Cross,Small,Big,None;",
    "-;",
    "D1OI,SuperFX Speed,Normal,Turbo;",
    "D3O4,CPU Speed,Normal,Turbo;",
    "-;",
    "R0,Reset;",
    "J1,A(SS Fire),B(SS Cursor),X(SS TurboSw),Y(SS Pause),LT(SS Cursor),RT(SS Fire),Select,Start;",
    "V,v",`BUILD_DATE
};
// free bits: 8,L,M

wire  [1:0] buttons;
wire [31:0] status;
wire [15:0] status_menumask = {!GUN_MODE, ~turbo_allow, ~gg_available, ~GSU_ACTIVE, ~bk_ena};
wire        forced_scandoubler;

//reg  [31:0] sd_lba;
wire [31:0] sd_lba_0;
wire [31:0] sd_lba_1;
wire [31:0] sd_lba_2;
wire [31:0] sd_lba_3;

reg   [3:0] sd_rd = 0;
reg   [3:0] sd_wr = 0;
wire  [3:0] sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        ioctl_download;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;

wire [11:0] joy0,joy1,joy2,joy3,joy4;
wire [24:0] ps2_mouse;

wire  [7:0] joy0_x,joy0_y,joy1_x,joy1_y;

reg  [15:0] msu_trackout = 0;
reg         msu_trackrequest = 0;
reg   		msu_trackmounting = 0;
reg         msu_trackmissing = 0;
reg			msu_trackmissing_reset = 0;
reg			msu_trackfinished = 0;
wire		msu_dataseekfinished_out;
wire [64:0] RTC;

hps_io #(.STRLEN($size(CONF_STR)>>3), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.conf_str(CONF_STR),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.new_vmode(new_vmode),

	.joystick_analog_0({joy0_y, joy0_x}),
	.joystick_analog_1({joy1_y, joy1_x}),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_2(joy2),
	.joystick_3(joy3),
	.joystick_4(joy4),
	.ps2_mouse(ps2_mouse),

	.msu_trackout(msu_trackout),
	.msu_trackrequest_in(msu_trackrequest),
	.msu_trackmounting(msu_trackmounting),
	.msu_trackmissing(msu_trackmissing),
	.msu_trackfinished(msu_trackfinished),

	.msu_data_seek(msu_data_seek_out),
	.msu_data_addr(msu_data_addr),
	.msu_dataseekfinished(msu_dataseekfinished_out),

	.status(status),
	.status_menumask(status_menumask),
	.status_in({status[31:5],1'b0,status[3:0]}),
	.status_set(cart_download),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),

	.sd_lba_0(sd_lba_0),
	.sd_lba_1(sd_lba_1),
	.sd_lba_2(sd_lba_2),
	.sd_lba_3(sd_lba_3),	
	
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	
	.RTC(RTC)
);

wire       GUN_BTN = status[27];
wire [1:0] GUN_MODE = status[26:25];
wire       GSU_TURBO = status[18];
wire       BLEND = ~status[16];
wire [1:0] mouse_mode = status[6:5];
wire       joy_swap = status[7];
wire [2:0] LHRom_type = status[3:1];

wire code_index = &ioctl_index;
wire code_download = ioctl_download & code_index;
wire cart_download = ioctl_download & ~code_index;

reg new_vmode;
always @(posedge clk_sys) begin
	reg old_pal;
	int to;
	
	if(~reset) begin
		old_pal <= PAL;
		if(old_pal != PAL) to <= 2000000;
	end
	
	if(to) begin
		to <= to - 1;
		if(to == 1) new_vmode <= ~new_vmode;
	end
end

//////////////////////////  ROM DETECT  /////////////////////////////////

reg        PAL;
reg  [7:0] rom_type;
reg [23:0] rom_mask, ram_mask;
always @(posedge clk_sys) begin
	reg [3:0] rom_size;
	reg [3:0] ram_size;
	reg       rom_region = 0;

	if (cart_download) begin
		if(ioctl_wr) begin
			if (ioctl_addr == 0) begin
				rom_size <= 4'hC;
				ram_size <= 4'h0;
				if(!LHRom_type && ioctl_dout[7:0]) {ram_size,rom_size} <= ioctl_dout[7:0];

				case(LHRom_type)
					1: rom_type <= 0;
					2: rom_type <= 0;
					3: rom_type <= 1;
					4: rom_type <= 2;
					default: rom_type <= ioctl_dout[15:8];
				endcase
			end

			if (ioctl_addr == 2) begin
				rom_region <= ioctl_dout[8];
			end

			if(LHRom_type == 2) begin
				if(ioctl_addr == ('h7FD6+'h200)) rom_size <= ioctl_dout[11:8];
				if(ioctl_addr == ('h7FD8+'h200)) ram_size <= ioctl_dout[3:0];
			end
			else if(LHRom_type == 3) begin
				if(ioctl_addr == ('hFFD6+'h200)) rom_size <= ioctl_dout[11:8];
				if(ioctl_addr == ('hFFD8+'h200)) ram_size <= ioctl_dout[3:0];
			end
			else if(LHRom_type == 4) begin
				if(ioctl_addr == ('h40FFD6+'h200)) rom_size <= ioctl_dout[11:8];
				if(ioctl_addr == ('h40FFD8+'h200)) ram_size <= ioctl_dout[3:0];
			end

			rom_mask <= (24'd1024 << rom_size) - 1'd1;
			ram_mask <= ram_size ? (24'd1024 << ram_size) - 1'd1 : 24'd0;
		end
	end
	else begin
		PAL <= (!status[15:14]) ? rom_region : status[15];
	end
end

////////////////////////////  SYSTEM  ///////////////////////////////////

wire GSU_ACTIVE;
wire turbo_allow;

reg [15:0] MAIN_AUDIO_L;
reg [15:0] MAIN_AUDIO_R;
reg msu_trig_play = 0;
reg msu_trig_pause = 0;

// Msu1 Audio
wire [7:0] msu_volume_out;
wire msu_repeat_out;
wire msu_audio_playing = msu_audio_play;
wire msu_audio_playing_out;

// Msu1 Data
wire [31:0] msu_data_addr;
wire [7:0] msu_data_in;
// busy status is a combination of fifo and dataseek (by the hps) states
wire msu_data_busy = msu_data_fifo_busy || (msu_dataseekfinished != 1);
wire msu_data_seek;

main main
(
	.RESET_N(~reset),

	.MCLK(clk_sys), // 21.47727 / 21.28137
	.ACLK(clk_sys),

	.GSU_ACTIVE(GSU_ACTIVE),
	.GSU_TURBO(GSU_TURBO),

	.MSU_TRACKOUT(msu_trackout),
	.MSU_TRACKREQUEST(msu_trackrequest),
	.MSU_TRACKMOUNTING(msu_trackmounting),
	.MSU_TRIG_PLAY(msu_trig_play),
	.MSU_TRIG_PAUSE(msu_trig_pause),
	
	.MSU_VOLUME_OUT(msu_volume_out),
	.MSU_REPEAT_OUT(msu_repeat_out),
	.MSU_AUDIO_PLAYING_IN(msu_audio_playing),
	.MSU_AUDIO_PLAYING_OUT(msu_audio_playing_out),
	.MSU_TRACKMISSING(msu_trackmissing),
	.MSU_TRACKFINISHED(msu_trackfinished),
	
	.MSU_DATA_ADDR(msu_data_addr),
	.MSU_DATA_IN(msu_data_in),
	.MSU_DATA_BUSY(msu_data_busy),
	.MSU_DATA_SEEK(msu_data_seek),
	.MSU_DATA_REQ(msu_data_req),

	.ROM_TYPE(rom_type),
	.ROM_MASK(rom_mask),
	.RAM_MASK(ram_mask),
	.PAL(PAL),
	.BLEND(BLEND),

	.ROM_ADDR(ROM_ADDR),
	.ROM_Q(ROM_Q),
	.ROM_CE_N(ROM_CE_N),
	.ROM_OE_N(ROM_OE_N),
	.ROM_WORD(ROM_WORD),

	.BSRAM_ADDR(BSRAM_ADDR),
	.BSRAM_D(BSRAM_D),			
	.BSRAM_Q(BSRAM_Q),			
	.BSRAM_CE_N(BSRAM_CE_N),
	.BSRAM_WE_N(BSRAM_WE_N),

	.WRAM_ADDR(WRAM_ADDR),
	.WRAM_D(WRAM_D),
	.WRAM_Q(WRAM_Q),
	.WRAM_CE_N(WRAM_CE_N),
	.WRAM_WE_N(WRAM_WE_N),

	.VRAM1_ADDR(VRAM1_ADDR),
	.VRAM1_DI(VRAM1_Q),
	.VRAM1_DO(VRAM1_D),
	.VRAM1_WE_N(VRAM1_WE_N),

	.VRAM2_ADDR(VRAM2_ADDR),
	.VRAM2_DI(VRAM2_Q),
	.VRAM2_DO(VRAM2_D),
	.VRAM2_WE_N(VRAM2_WE_N),

	.ARAM_ADDR(ARAM_ADDR),
	.ARAM_D(ARAM_D),
	.ARAM_Q(ARAM_Q),
	.ARAM_CE_N(ARAM_CE_N),
	.ARAM_WE_N(ARAM_WE_N),

	.R(R),
	.G(G),
	.B(B),

	.FIELD(FIELD),
	.INTERLACE(INTERLACE),
	.HIGH_RES(HIGH_RES),
	.DOTCLK(DOTCLK),
	
	.HBLANKn(HBlank_n),
	.VBLANKn(VBlank_n),
	.HSYNC(HSYNC),
	.VSYNC(VSYNC),

	.JOY1_DI(JOY1_DI),
	.JOY2_DI(GUN_MODE ? LG_DO : JOY2_DI),
	.JOY_STRB(JOY_STRB),
	.JOY1_CLK(JOY1_CLK),
	.JOY2_CLK(JOY2_CLK),
	.JOY1_P6(JOY1_P6),
	.JOY2_P6(JOY2_P6),
	.JOY2_P6_in(JOY2_P6_DI),
	
	.EXT_RTC(RTC),

	.GG_EN(status[24]),
	.GG_CODE(gg_code),
	.GG_RESET((code_download && ioctl_wr && !ioctl_addr) || cart_download),
	.GG_AVAILABLE(gg_available),
	
	.TURBO(status[4] & turbo_allow),
	.TURBO_ALLOW(turbo_allow),

	.AUDIO_L(MAIN_AUDIO_L),
	.AUDIO_R(MAIN_AUDIO_R)
);

wire signed [16:0] AUDIO_MIX_L = $signed({MAIN_AUDIO_L[15], MAIN_AUDIO_L}) + $signed({msu_audio_l[15], msu_audio_l});
wire signed [16:0] AUDIO_MIX_R = $signed({MAIN_AUDIO_R[15], MAIN_AUDIO_R}) + $signed({msu_audio_r[15], msu_audio_r});

assign AUDIO_L = AUDIO_MIX_L[16:1];
assign AUDIO_R = AUDIO_MIX_R[16:1];

////////////////////////////  CODES  ///////////////////////////////////

reg [128:0] gg_code;
wire gg_available;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_dout; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_dout; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_dout; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_dout; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_dout; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_dout; // Compare top Word
			12: gg_code[15:0]    <= ioctl_dout; // Replace Bottom Word
			14: begin
				gg_code[31:16]    <= ioctl_dout; // Replace Top Word
				gg_code[128]      <= 1;          // Clock it in
			end
		endcase
	end
end

////////////////////////////  MEMORY  ///////////////////////////////////

wire[23:0] ROM_ADDR;
wire       ROM_CE_N;
wire       ROM_OE_N;
wire       ROM_WORD;
wire[15:0] ROM_Q;

sdram sdram
(
	.*,
	.init(0), //~clock_locked),
	.clk(clk_mem),
	
	.addr(cart_download ? ioctl_addr-10'd512 : ROM_ADDR),
	.din(ioctl_dout),
	.dout(ROM_Q),
	.rd(~cart_download & ~ROM_CE_N & ~ROM_OE_N),
	.wr(ioctl_wr & cart_download),
	.word(cart_download | ROM_WORD),
	.busy()
);

wire[16:0] WRAM_ADDR;
wire       WRAM_CE_N;
wire       WRAM_WE_N;
wire [7:0] WRAM_Q, WRAM_D;
dpram #(17)	wram
(
	.clock(clk_sys),
	.address_a(WRAM_ADDR),
	.data_a(WRAM_D),
	.wren_a(~WRAM_CE_N & ~WRAM_WE_N),
	.q_a(WRAM_Q),

	// clear the RAM on loading
	.address_b(ioctl_addr[16:0]),
	.wren_b(ioctl_wr & cart_download)
);

wire [15:0] VRAM1_ADDR;
wire        VRAM1_WE_N;
wire  [7:0] VRAM1_D, VRAM1_Q;
dpram #(15)	vram1
(
	.clock(clk_sys),
	.address_a(VRAM1_ADDR[14:0]),
	.data_a(VRAM1_D),
	.wren_a(~VRAM1_WE_N),
	.q_a(VRAM1_Q),

	// clear the RAM on loading
	.address_b(ioctl_addr[14:0]),
	.wren_b(ioctl_wr & cart_download)
);

wire [15:0] VRAM2_ADDR;
wire        VRAM2_WE_N;
wire  [7:0] VRAM2_D, VRAM2_Q;
dpram #(15) vram2
(
	.clock(clk_sys),
	.address_a(VRAM2_ADDR[14:0]),
	.data_a(VRAM2_D),
	.wren_a(~VRAM2_WE_N),
	.q_a(VRAM2_Q),

	// clear the RAM on loading
	.address_b(ioctl_addr[14:0]),
	.wren_b(ioctl_wr & cart_download)
);

wire [15:0] ARAM_ADDR;
wire        ARAM_CE_N;
wire        ARAM_WE_N;
wire  [7:0] ARAM_Q, ARAM_D;
dpram #(16) aram
(
	.clock(clk_sys),
	.address_a(ARAM_ADDR),
	.data_a(ARAM_D),
	.wren_a(~ARAM_CE_N & ~ARAM_WE_N),
	.q_A(ARAM_Q),

	// clear the RAM on loading
	.address_b(ioctl_addr[15:0]),
	.wren_b(ioctl_wr & cart_download)
);

localparam  BSRAM_BITS = 17; // 1Mbits
wire [19:0] BSRAM_ADDR;
wire        BSRAM_CE_N;
wire        BSRAM_WE_N;
wire  [7:0] BSRAM_Q, BSRAM_D;
dpram_dif #(BSRAM_BITS,8,BSRAM_BITS-1,16) bsram 
(
	.clock(clk_sys),

	//Thrash the BSRAM upon ROM loading
	.address_a(cart_download ? ioctl_addr[BSRAM_BITS-1:0] : BSRAM_ADDR[BSRAM_BITS-1:0]),
	.data_a(cart_download ? ioctl_addr[7:0] : BSRAM_D),
	.wren_a(cart_download ? ioctl_wr : ~BSRAM_CE_N & ~BSRAM_WE_N),
	.q_a(BSRAM_Q),

	.address_b({sd_lba_0[BSRAM_BITS-10:0],sd_buff_addr}),
	.data_b(sd_buff_dout),
	.wren_b(sd_buff_wr & sd_ack[0]),
	.q_b(sd_buff_din)
);

////////////////////////////  VIDEO  ////////////////////////////////////

wire [7:0] R,G,B;
wire FIELD,INTERLACE;
wire HSync, HSYNC;
wire VSync, VSYNC;
wire HBlank_n;
wire VBlank_n;
wire HIGH_RES;
wire DOTCLK;

reg interlace;
reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [2:0] pcnt;
	reg old_vsync;
	reg tmp_hres, frame_hres;
	reg old_dotclk;
	
	tmp_hres <= tmp_hres | HIGH_RES;

	old_vsync <= VSync;
	if(~old_vsync & VSync) begin
		frame_hres <= tmp_hres | ~scandoubler;
		tmp_hres <= HIGH_RES;
		interlace <= INTERLACE;
	end

	pcnt <= pcnt + 1'd1;
	old_dotclk <= DOTCLK;
	if(~old_dotclk & DOTCLK & HBlank_n & VBlank_n) pcnt <= 1;

	ce_pix <= !pcnt[1:0] & (frame_hres | ~pcnt[2]);
	
	if(pcnt==3) {HSync, VSync} <= {HSYNC, VSYNC};
end

assign VGA_F1 = interlace & FIELD;
assign VGA_SL = {~interlace,~interlace}&sl[1:0];

wire [2:0] scale = status[11:9];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
wire       scandoubler = ~interlace && (scale || forced_scandoubler);

video_mixer #(.LINE_LENGTH(520)) video_mixer
(
	.*,

	.clk_sys(CLK_VIDEO),
	.ce_pix_out(CE_PIXEL),

	.scanlines(0),
	.hq2x(scale==1),
	.mono(0),

	.HBlank(~HBlank_n),
	.VBlank(~VBlank_n),
	.R((LG_TARGET && GUN_MODE && (!status[29] | LG_T)) ? {8{LG_TARGET[0]}} : R),
	.G((LG_TARGET && GUN_MODE && (!status[29] | LG_T)) ? {8{LG_TARGET[1]}} : G),
	.B((LG_TARGET && GUN_MODE && (!status[29] | LG_T)) ? {8{LG_TARGET[2]}} : B)
);

////////////////////////////  I/O PORTS  ////////////////////////////////

wire       JOY_STRB;

wire [1:0] JOY1_DO;
wire       JOY1_CLK;
wire       JOY1_P6;
ioport port1
(
	.CLK(clk_sys),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY1_CLK),
	.PORT_P6(JOY1_P6),
	.PORT_DO(JOY1_DO),

	.JOYSTICK1((joy_swap ^ raw_serial) ? joy1 : joy0),

	.MOUSE(ps2_mouse),
	.MOUSE_EN(mouse_mode[0])
);

wire [1:0] JOY2_DO;
wire       JOY2_CLK;
wire       JOY2_P6;
ioport port2
(
	.CLK(clk_sys),

	.MULTITAP(status[17]),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY2_CLK),
	.PORT_P6(JOY2_P6),
	.PORT_DO(JOY2_DO),

	.JOYSTICK1((joy_swap ^ raw_serial) ? joy0 : joy1),
	.JOYSTICK2(joy2),
	.JOYSTICK3(joy3),
	.JOYSTICK4(joy4),

	.MOUSE(ps2_mouse),
	.MOUSE_EN(mouse_mode[1])
);

wire       LG_P6_out;
wire [1:0] LG_DO;
wire [2:0] LG_TARGET;
wire       LG_T = ((GUN_MODE[0]&joy0[6]) | (GUN_MODE[1]&joy1[6])); // always from joysticks

lightgun lightgun
(
	.CLK(clk_sys),
	.RESET(reset),

	.MOUSE(ps2_mouse),
	.MOUSE_XY(&GUN_MODE),

	.JOY_X(GUN_MODE[0] ? joy0_x : joy1_x),
	.JOY_Y(GUN_MODE[0] ? joy0_y : joy1_y),

	.F(GUN_BTN ? ps2_mouse[0] : ((GUN_MODE[0]&(joy0[4]|joy0[9]) | (GUN_MODE[1]&(joy1[4]|joy1[9]))))),
	.C(GUN_BTN ? ps2_mouse[1] : ((GUN_MODE[0]&(joy0[5]|joy0[8]) | (GUN_MODE[1]&(joy1[5]|joy0[8]))))),
	.T(LG_T), // always from joysticks
	.P(ps2_mouse[2] | ((GUN_MODE[0]&joy0[7]) | (GUN_MODE[1]&joy1[7]))), // always from joysticks and mouse

	.HDE(HBlank_n),
	.VDE(VBlank_n),
	.CLKPIX(DOTCLK),
	
	.TARGET(LG_TARGET),
	.SIZE(status[28]),

	.PORT_LATCH(JOY_STRB),
	.PORT_CLK(JOY2_CLK),
	.PORT_P6(LG_P6_out),
	.PORT_DO(LG_DO)
);

///////////////////////////  MSU Audio  ///////////////////////////////
// Please use SD2SNES compatible MSU1 hacks *only*
//
// Many thanks to ElectronAsh and Qwertymodo for helping me get my head around this
// Respect to Ash who helped with setting up things for me to bug fix, and for teaching me
// how to think like a FPGA programmer a little more! 
// Respect to Qwertymodo for creating msu1.sfc! An extremely useful tool in the early phases
// of development.
//
// Thanks to Amoore2600, Uigiflip, BrunoSilva, for testing
// Much thanks to JFT, Steve Fox, Mike SmokeMonster for their donations/assistance

// State of playing in the msu_audio instance
(*noprune*) reg msu_audio_play = 0;

reg left_chan = 0;
reg [15:0] temp_l;
reg [15:0] samp_l;
reg [15:0] samp_r;
reg [9:0] audio_clk_div = 0;

// MSU audio sample player - Pulls samples out of the FIFO buffer
always @(posedge CLK_50M) begin
	// The first sample of a MSU PCM file should be the LEFT sample. (ignoring the two header words).
	// The rest of the samples should be contiguously interleaved (LEFt/RIGHT) from that point on.
	if (sd_ack[1] && sd_lba_1==0 && msu_audio_word_count==4) left_chan <= 1'b1;	
	
	if (audio_clk_div > 0) audio_clk_div <= audio_clk_div - 1;	
	else begin
		left_chan <= !left_chan;
		audio_clk_div <= 566;
		
		// left then right samples
		if (left_chan) temp_l <= audio_fifo_dout;
		else begin
			// Make sure both the left and right samples get output at the same time.
			samp_l <= temp_l;
			samp_r <= audio_fifo_dout;
		end
	end
end

// The MSU audio PCM files contain the "MSU1" ASCII in the first two WORDs,
// followed by two more words that contain the loop index (in SAMPLES), for when repeat mode is active.
//
// (sd_lba_1==0, to check only the first sector).
wire msu_header_skip = sd_lba_1==0 && (msu_audio_word_count >= 0 && msu_audio_word_count <= 3);

(*keep*) wire audio_clk_en = (audio_clk_div==1);
(*keep*) wire audio_fifo_reset = RESET | msu_trackmounting | msu_trackmissing_reset | cart_download;
(*keep*) wire audio_fifo_full;
(*keep*) wire audio_fifo_wr = !audio_fifo_full && sd_ack[1] && sd_buff_wr && !msu_header_skip && !ignore_sd_buffer_out;
(*keep*) wire [11:0] audio_fifo_usedw;
(*keep*) wire audio_fifo_empty;
(*keep*) wire audio_fifo_rd = !audio_fifo_empty && audio_clk_en && msu_audio_play;
(*keep*) wire [15:0] audio_fifo_dout;

reg [15:0] msu_audio_l;
reg [15:0] msu_audio_r;

msu_audio_fifo msu_audio_fifo_inst (
	.aclr(audio_fifo_reset),
	.wrclk(clk_sys),
	.wrreq(audio_fifo_wr),
	.wrfull(audio_fifo_full),
	.wrusedw(audio_fifo_usedw),
	.data(sd_buff_dout),
	.rdclk(CLK_50M),
	.rdreq(audio_fifo_rd),
	.rdempty(audio_fifo_empty),
	.q(audio_fifo_dout)
);

wire sd_ack_1 = sd_ack[1];
reg ignore_sd_buffer_out = 0;

msu_audio msu_audio_inst (
	.clk(clk_sys),
  	.reset(reset),
  	.img_size(img_size),
  	.trig_play(msu_trig_play),
	.trig_pause(msu_trig_pause),
	.sd_ack_1(sd_ack[1]),
  	.repeat_in(msu_repeat_out),
  	.trackmounting(msu_trackmounting),
	.trackmissing(msu_trackmissing),
	.trackfinished(msu_trackfinished),
  	.sd_buff_wr(sd_buff_wr),
	.sd_buff_dout(sd_buff_dout),
  	.audio_fifo_usedw(audio_fifo_usedw),  
  	.sd_lba_1(sd_lba_1),
	.ignore_sd_buffer_out(ignore_sd_buffer_out),
  	.audio_play(msu_audio_play),
	.audio_play_in(msu_audio_playing_out),
	.word_count(msu_audio_word_count),
  	.sd_rd_1(sd_rd[1]),
	.trackmissing_reset(msu_trackmissing_reset)
);

wire signed [8:0] msu_vol_signed = {1'b0, msu_volume_out};
wire signed [23:0] msu_vol_mix_l = $signed(samp_l) * msu_vol_signed;
wire signed [23:0] msu_vol_mix_r = $signed(samp_r) * msu_vol_signed;
assign msu_audio_l = (msu_audio_play) ? msu_vol_mix_l[23:8] : 16'h0000;
assign msu_audio_r = (msu_audio_play) ? msu_vol_mix_r[23:8] : 16'h0000;

/////////////////////////  MSU Data //////////////////////////////

(*noprune*) reg [7:0] msu_data_debug = 0;
(*noprune*) reg msu_dataseekfinished = 0;
(*noprune*) reg msu_data_fifo_busy = 0;
(*noprune*) reg msu_data_seek_out = 0;

// MSU Data track reading state machine
always @(posedge clk_sys or posedge reset)
if (reset) begin
	// pause the state machine
	msu_data_state <= 8'd4;
	msu_data_wordcount <= 0;
	sd_lba_2 <= 0;
	sd_rd[2] <= 0;

	allow_data_fifo_wr <= 1'b0;

	msu_data_addr_bit1_old <= 0;

	msu_data_fifo_busy <= 1'b0;
	msu_dataseekfinished <= 0;
	msu_dataseekfinished_out_old <= 0;
	msu_data_debug <= 8'd0;
end
else begin

	msu_data_debug <= 8'd0;

	// falling edge stuff
	msu_data_addr_bit1_old <= msu_data_addr[1];
	msu_dataseekfinished_out_old <= msu_dataseekfinished_out;

	if (msu_dataseekfinished_out_old && ~msu_dataseekfinished_out) begin
		msu_data_debug <= 8'd66;
		msu_data_seek_out <= 0;
		msu_dataseekfinished <= 1;
	end

	if (msu_data_seek) begin
		// Both our fifo and hps are seeking
		msu_data_fifo_busy <= 1'b1;
		msu_dataseekfinished <= 0;
		// Init sd, fifo, internal counters
		sd_lba_2 <= 0;
		allow_data_fifo_wr <= 1'b1;
		msu_data_wordcount <= 8'd0;
		sd_rd[2] <= 1'b0;
		// Tell the hps to seek now
		msu_data_seek_out <= 1;

		// Kick off the state machine
		msu_data_state <= 0;
	end	
	
	case (msu_data_state)
	0: begin
		sd_rd[2] <= 1'b1;
		msu_data_wordcount <= 8'd0;
	
		// if (msu_data_byte_offset > 0) begin
		// 	msu_data_debug <= 8'd3;
		// 	// If the byte offset (within a sector boundary) is non-zero, then we have to
		// 	// inhibit writes to the data FIFO until we see the correct offset
		// 	allow_data_fifo_wr <= 1'b0;
		// end else begin
		// 	msu_data_debug <= 8'd4;
		// end

		msu_data_state <= msu_data_state + 1;
	end
		
	1: if (sd_ack[2]) begin
		// Sector transfer has started. (Need to check sd_ack[2], so we know the data is for us.)
		sd_rd[2] <= 1'b0;
		msu_data_state <= msu_data_state + 1;
	end
	
	2: begin
		// Only allow writes to the FIFO once the current WORD offset (from the HPS transfer)
		// matches the requested WORD offset (from the MSU)...
		//if (msu_data_wordcount >= msu_data_byte_offset >> 1) allow_data_fifo_wr <= 1'b1;
	
		if (sd_ack[2] && sd_buff_wr) begin
			msu_data_wordcount <= msu_data_wordcount + 1;
		end
		
		// See if we have filled up our 32 sector (16kb) buffer yet BEFORE we say our seek is finished
		if (!sd_ack[2] & sd_lba_2 >= 32'd30) begin
			// Let the MSU know the seek has finished, at least in terms of the fifo buffer, hps could still
			// be seeking... Doesn't matter, we can start reading stuff out of the buffer
			msu_data_fifo_busy <= 1'b0;
			msu_data_state <= msu_data_state + 1;
			
			msu_data_debug <= 8'd7;
		end else if (!sd_ack[2]) begin
			msu_data_state <= msu_data_state + 1;
			msu_data_debug <= 8'd6;
		end
	end

	3: begin
		// Keep topping up the fifo, but only if it's not near full. (16kb - 512 bytes = 7936 words)
		if (msu_data_fifo_usedw < 16'd7936) begin
			sd_lba_2 <= sd_lba_2 + 1;
			msu_data_state <= 0;
			msu_data_debug <= 8'd2;
		end
		// Otherwise pause in this state
	end

	4: begin
		// Initial 'Paused' state
		msu_data_debug <= 8'd5;
	end
	
	default:;
	endcase
end

wire msu_data_req;
// 512 bytes in a sector
wire [8:0] msu_data_byte_offset = msu_data_addr[8:0];
// Clear the FIFO, for only ONE clock pulse, else it will clear the first sector we transfer.
wire msu_data_fifo_clear = msu_data_seek || reset;
// Flag used to inhibit writes to the data FIFO when the seek address is not on a 512-byte sector boundary.
(*noprune*) reg allow_data_fifo_wr;
initial allow_data_fifo_wr = 1;

wire msu_data_fifo_wr = !msu_data_fifo_full && allow_data_fifo_wr && sd_ack[2] && sd_buff_wr;
wire [15:0] msu_data_fifo_dout;
wire msu_data_fifo_empty;
wire msu_data_fifo_full;
wire [15:0] msu_data_fifo_usedw;

reg msu_data_addr_bit1_old = 0;
reg msu_dataseekfinished_out_old = 0;

wire msu_data_fifo_rdreq = msu_data_req && (msu_data_addr_bit1_old != msu_data_addr[1]);

msu_data_fifo msu_data_fifo_inst (
	.aclr(msu_data_fifo_clear),
	.clock(clk_sys),
	.wrreq(msu_data_fifo_wr),
	.full(msu_data_fifo_full),
	.usedw(msu_data_fifo_usedw),
	.data(sd_buff_dout),
	.rdreq(msu_data_fifo_rdreq),
	.empty(msu_data_fifo_empty),
	.q(msu_data_fifo_dout)	
);

(*noprune*) reg [7:0] msu_data_state = 2'd4;
(*noprune*) reg [7:0] msu_data_wordcount = 2'd0;

// Select the lower or upper byte from the 16-bit data from the buffer, depending on the LSB bit of msu_data_addr...
// (because hps_io is set up to transfer 16-bit words, which is handy for audio track playback, but msu_data reads 
// are 8-bit.) ElectronAsh
assign msu_data_in = (!msu_data_addr[0]) ? msu_data_fifo_dout[7:0] : msu_data_fifo_dout[15:8];

/// MSU DATA ENDS ///

// Indexes:
// 0 = D+    = Latch
// 1 = D-    = CLK
// 2 = TX-   = P5
// 3 = GND_d
// 4 = RX+   = P6
// 5 = RX-   = P4

wire raw_serial = status[8];

assign USER_OUT[2] = 1'b1;
assign USER_OUT[3] = 1'b1;
assign USER_OUT[5] = 1'b1;
assign USER_OUT[6] = 1'b1;

// JOYX_DO[0] is P4, JOYX_DO[1] is P5
wire [1:0] JOY1_DI;
wire [1:0] JOY2_DI;
wire JOY2_P6_DI;

always_comb begin
	if (raw_serial) begin
		USER_OUT[0] = JOY_STRB;
		USER_OUT[1] = joy_swap ? ~JOY2_CLK : ~JOY1_CLK;
		USER_OUT[4] = joy_swap ? JOY2_P6 : JOY1_P6;
		JOY1_DI = joy_swap ? JOY1_DO : {USER_IN[2], USER_IN[5]};
		JOY2_DI = joy_swap ? {USER_IN[2], USER_IN[5]} : JOY2_DO;
		JOY2_P6_DI = joy_swap ? USER_IN[4] : (LG_P6_out | !GUN_MODE);
	end else begin
		USER_OUT[0] = 1'b1;
		USER_OUT[1] = 1'b1;
		USER_OUT[4] = 1'b1;
		JOY1_DI = JOY1_DO;
		JOY2_DI = JOY2_DO;
		JOY2_P6_DI = (LG_P6_out | !GUN_MODE);
	end
end

/////////////////////////  STATE SAVE/LOAD  /////////////////////////////

wire bk_save_write = ~BSRAM_CE_N & ~BSRAM_WE_N;
reg bk_pending;

always @(posedge clk_sys) begin
	if (bk_ena && ~OSD_STATUS && bk_save_write)
		bk_pending <= 1'b1;
	else if (bk_state)
		bk_pending <= 1'b0;
end

reg bk_ena = 0;
reg old_downloading = 0;
always @(posedge clk_sys) begin
	old_downloading <= cart_download;
	if(~old_downloading & cart_download) bk_ena <= 0;
	
	// Save file always mounted in the end of downloading state.
	if(cart_download && img_mounted && !img_readonly) bk_ena <= |ram_mask;
end

wire bk_load    = status[12];
wire bk_save    = status[13] | (bk_pending & OSD_STATUS && status[23]);
reg  bk_loading = 0;

reg  [1:0] bk_state = 0;

always @(posedge clk_sys) begin
 	reg old_load = 0, old_save = 0, old_ack;

 	old_load <= bk_load & bk_ena;
	old_save <= bk_save & bk_ena;
 	old_ack  <= sd_ack[0];

 	if(~old_ack & sd_ack[0]) {sd_rd[0], sd_wr[0]} <= 0;
	
	if (!bk_state) begin	// bk_state==0.
 		if((~old_load & bk_load) | (~old_save & bk_save)) begin
 			bk_loading <= bk_load;
 			sd_lba_0 <= 0;
 			sd_rd[0] <=  bk_load;
 			sd_wr[0] <= ~bk_load;
			bk_state <= 1;
 		end
 		if(old_downloading & ~cart_download & |img_size & bk_ena) begin
 			bk_loading <= 1;
			sd_lba_0 <= 0;
 			sd_rd[0] <= 1;
 			sd_wr[0] <= 0;
			bk_state <= 1;
 		end
	end
	else begin	// bk_state==1.
 		if(old_ack & ~sd_ack[0]) begin
			if(sd_lba_0 >= ram_mask[23:9]) begin
 				bk_loading <= 0;
 				bk_state <= 0;
 			end else begin
 				sd_lba_0 <= sd_lba_0 + 1'd1;
 				sd_rd[0]  <=  bk_loading;
 				sd_wr[0]  <= ~bk_loading;
 			end
 		end
 	end
end
 
endmodule
