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
    output    [31:0] addr_out,
    output    [15:0] track_out,
    output     [7:0] status_out,
    output     [7:0] volume_out
);

// Read 'registers'
// MSU_STATUS - $2000
// Status bits
reg msu_status_data_busy;
reg msu_status_audio_busy;
reg msu_status_audio_repeat;
reg msu_status_audio_playing;
reg msu_status_track_missing;
localparam [2:0] msu_status_revision = 3'b001;
wire [7:0] MSU_STATUS = {msu_status_data_busy, msu_status_audio_busy, msu_status_audio_repeat, msu_status_audio_playing, msu_status_track_missing, msu_status_revision}; 

// MSU_READ - $2001
reg [13:0] msu_address_r;
wire [13:0] msu_address = msu_address_r;
initial msu_address_r = 13'b0;
reg msu_data;
reg [7:0] MSU_READ;

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
reg  [7:0] MSU_SEEK;                      // $2000 - $2003
reg [15:0] MSU_TRACK;                     // $2004 - $2005
reg  [7:0] MSU_VOLUME;                    // $2006
reg  [7:0] MSU_CONTROL;                   // $2007
reg [31:0] MSU_ADDR;

assign addr_out = MSU_ADDR;
assign track_out = MSU_TRACK;

always @(posedge CLK) begin
	if (~RST_N) begin
        // Handle RESET
        MSU_SEEK <= 0;
        MSU_TRACK <= 0;
        MSU_VOLUME <= 0;
        MSU_CONTROL <= 0;
        DOUT <= 0;
    end else begin
        // Register writes
        if (ENABLE & ~WR_N) begin
            case (ADDR[15:0])
                // MSU_Track LSB
                16'h2004: begin
                    MSU_TRACK[7:0] <= DIN;
                end
                // MSU_Track MSB
                16'h2005: begin    
                    MSU_TRACK[15:8] <= DIN;
                    msu_status_audio_busy <= 1;
                end
                default: $display("nothing");
            endcase 
        end else if (ENABLE & ~RD_N) begin
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
                        msu_address_r <= msu_address_r + 1;
                    end
                    DOUT <= MSU_READ;
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
                default: $display("nothing");
            endcase
        end
    end
end

endmodule