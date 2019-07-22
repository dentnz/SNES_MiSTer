module MSU(
	input CLK,

	input ENABLE,
	input RD_N,
	input WR_N,
	input RST_N,

	input [23:0] ADDR,
	input      [7:0] DIN,
	output reg [7:0] DOUT,

	// Stuff for the HPS
	output     [31:0] addr_out,
	output reg [15:0] track_out,
	input             track_mounting,
	output      [7:0] volume_out,
	output            trig_play,
 
	output reg msu_status_audio_busy,
	output reg msu_status_audio_repeat,
	output reg msu_status_audio_playing,
	output reg msu_status_track_missing,
	
	output reg [31:0] msu_data_addr,
	input [7:0] msu_data_in,
	input msu_status_data_busy
);

assign volume_out = MSU_VOLUME;

// Read 'registers'
// MSU_STATUS - $2000
// Status bits
localparam [2:0] msu_status_revision = 3'b001;
wire [7:0] MSU_STATUS = {msu_status_data_busy, msu_status_audio_busy, msu_status_audio_repeat, msu_status_audio_playing, msu_status_track_missing, msu_status_revision}; 

// MSU_READ - $2001
//reg [31:0] msu_data_addr;
//initial msu_data_addr = 32'h00000000;
//reg msu_data;
//reg [7:0] MSU_READ;

// MSU_ID - $2002 to $2007
// 'S-MSU1' identity string is at MSU_ID during reading of $2002 to $2007
wire [7:0] MSU_ID [0:5];
assign MSU_ID[0] = "S";
assign MSU_ID[1] = "-";
assign MSU_ID[2] = "M";
assign MSU_ID[3] = "S";
assign MSU_ID[4] = "U";
// Can be updated at a later stage should MSU-2 become available
assign MSU_ID[5] = "1";

// Write registers
reg [31:0] MSU_SEEK;                      // $2000 - $2003
reg [15:0] MSU_TRACK;                     // $2004 - $2005
reg  [7:0] MSU_VOLUME;                    // $2006
reg  [7:0] MSU_CONTROL;                   // $2007
reg [31:0] MSU_ADDR;

assign addr_out = MSU_ADDR;
assign msu_status_audio_busy = ~track_mounting;

// Make sure we are aware of which bank ADDR is currently in 
(*keep*) wire IO_BANK_SEL = (ADDR[23:16]>=8'h00 && ADDR[23:16]<=8'h3F) || (ADDR[23:16]>=8'h80 && ADDR[23:16]<=8'hBF);

always @(posedge CLK) begin
	if (~RST_N) begin
        // Handle RESET
        MSU_SEEK <= 0;
        MSU_TRACK <= 0;
        MSU_VOLUME <= 0;
        MSU_CONTROL <= 0;
        DOUT <= 0;
    end else begin
        // Reset our play trigger
        trig_play <= 1'b0;

        // Register writes
        if (ENABLE & ~WR_N & IO_BANK_SEL)   begin
            case (ADDR[15:0])
					// Data seek address. MSU_SEEK, LSB byte.
					16'h2000: begin
						MSU_SEEK[7:0] <= DIN;
					end
					// Data seek address. MSU_SEEK.
					16'h2001: begin
						MSU_SEEK[15:8] <= DIN;
					end
					// Data seek address. MSU_SEEK.
					16'h2002: begin
						MSU_SEEK[23:16] <= DIN;
					end
					// Data seek address. MSU_SEEK, MSB byte.
					16'h2003: begin
                        // A write to 0x2003 triggers the update of msu_data_addr.
						msu_data_addr <= {DIN, MSU_SEEK[23:0]};
					end
					// MSU_Track LSB
					16'h2004: begin
					    MSU_TRACK[7:0] <= DIN;
					end
					// MSU_Track MSB
					16'h2005: begin    
					    MSU_TRACK[15:8] <= DIN;
                        // Only update track_out when both (upper and lower) bytes arrive. ElectronAsh.
					    track_out <= {DIN, MSU_TRACK[7:0]};	
					    // trigger play... will be reset on next CLK
					    trig_play <= 1;
					end
					// MSU Audio Volume. (MSU_VOLUME).
					16'h2006: begin
					    MSU_VOLUME <= DIN;
					end
					// MSU Audio state control. (MSU_CONTROL).
					16'h2007: begin
					    msu_status_audio_playing <= DIN[0];
					    msu_status_audio_repeat  <= DIN[1];
					end
					default:;
				endcase 
        end else if (ENABLE & ~RD_N & IO_BANK_SEL) begin
        // Register reads
            case (ADDR[15:0])
                // MSU_STATUS
                16'h2000: begin
                    DOUT <= MSU_STATUS;
                end
                // MSU_READ
                16'h2001: begin
                    if (!msu_status_data_busy) begin
                        // Data reads increase the memory address by 1
                        msu_data_addr <= msu_data_addr + 1;
                    end
					DOUT <= msu_data_in;
                end
                // MSU_ID
                16'h2002: begin
                    DOUT <= MSU_ID[0];
                end
                16'h2003: begin
                    DOUT <= MSU_ID[1];
                end
                16'h2004: begin
                    DOUT <= MSU_ID[2];
                end
                16'h2005: begin
                    DOUT <= MSU_ID[3];
                end
                16'h2006: begin
                    DOUT <= MSU_ID[4];
                end
                16'h2007: begin
                    DOUT <= MSU_ID[5];
                end
                default:;
            endcase
        end
    end
end

endmodule