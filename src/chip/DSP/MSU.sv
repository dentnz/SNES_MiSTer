module MSU(
    input CLK,

    input ENABLE,
    input RD_N,
    input WR_N,
    input RST_N,

    input [23:0] ADDR,
    input      [7:0] DIN,
    output reg [7:0] DOUT,

    // Audio HPS control
    output     [31:0] addr_out,
    output reg [15:0] track_out,
    input             track_mounting,

    // Audio player control
    output reg        trig_play,
    output reg [7:0] volume_out,

    output reg msu_status_audio_busy,
    output reg msu_status_audio_repeat,
    // This should contain if the msu_audio instance is currently playing
    input  reg msu_status_audio_playing_in,
    // This should output play/stop coming from game code poking MSU_CONTROL 
    output reg msu_status_audio_playing_out,
    
    input  msu_status_track_missing,
    
    output reg [31:0] msu_data_addr = 0,
    input [7:0] msu_data_in,
    input msu_status_data_busy,
    output reg msu_data_seek,
    output reg [7:0] dbg_msu_reg
);

initial begin
    msu_status_audio_busy = 0;
    msu_status_audio_repeat = 0;
    msu_status_audio_playing_out = 0;
    msu_data_addr = 0;
    track_out = 0;
    trig_play = 0;
    dbg_msu_reg = 0;
end

assign volume_out = MSU_VOLUME;

// Read 'registers'
// MSU_STATUS - $2000
// Status bits
localparam [2:0] msu_status_revision = 3'b001;
wire [7:0] MSU_STATUS = {msu_status_data_busy, msu_status_audio_busy, msu_status_audio_repeat, msu_status_audio_playing_out, msu_status_track_missing, msu_status_revision}; 

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
// @todo might need this - Track seek time is given a busy bit in the official implementation
//assign msu_status_audio_busy = track_mounting;

// Make sure we are aware of which bank ADDR is currently in 
(*keep*) wire IO_BANK_SEL = (ADDR[23:16]>=8'h00 && ADDR[23:16]<=8'h3F) || (ADDR[23:16]>=8'h80 && ADDR[23:16]<=8'hBF);

// Rising and falling edge detection
reg RD_N_1 = 1'b1;
reg WR_N_1 = 1'b1;

always @(posedge CLK or negedge RST_N) begin
    if (~RST_N) begin
        // Handle RESET
        MSU_SEEK <= 0;
        MSU_TRACK <= 0;
        MSU_VOLUME <= 0;
        MSU_CONTROL <= 0;
        msu_status_audio_playing_out <= 0;
        msu_status_audio_repeat <= 0;
        DOUT <= 0;
        trig_play <= 1'b0;
        msu_data_seek <= 1'b0;
        msu_data_addr <= 32'h00000000;
        RD_N_1 <= 1'b1;
        WR_N_1 <= 1'b1;
        dbg_msu_reg <= 8'd1;
    end else begin
        // Reset our play triggers for pulsing
        trig_play <= 1'b0;
        msu_data_seek <= 1'b0;

        // Rising and falling edge detection
        RD_N_1 <= RD_N;
        WR_N_1 <= WR_N;
          
        // RISING edge of RD_N, when it goes to idle
        // So the address increments AFTER the SNES has read the data from the CURRENT address.
        // 0x2001 = MSU DATA Port.
        if (ENABLE && IO_BANK_SEL && ADDR[15:0]==16'h2001 && (!RD_N_1 && RD_N) ) begin
            msu_data_addr <= msu_data_addr + 1;
        end

        // FALLING edge of WR_N.
        // 0x2003 = MSU SEEK Port
        if (ENABLE && IO_BANK_SEL && ADDR[15:0]==16'h2003 && (WR_N_1 && !WR_N) ) begin
            // A write to 0x2003 triggers the update of msu_data_addr...
            msu_data_addr <= {DIN, MSU_SEEK[23:0]};
            // And a SINGLE clock pulse of msu_data_seek
            msu_data_seek <= 1'b1;
        end
        
        // FALLING edge of WR_N.
        // 0x2007 = MSU CONTROL
        if (ENABLE && IO_BANK_SEL && ADDR[15:0] == 16'h2007 && (WR_N_1 && !WR_N)) begin
            trig_play <= 1;
        end
              
        // Register writes
        if (ENABLE & ~WR_N & IO_BANK_SEL) begin
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
                    //MSU_SEEK[31:24] <= DIN;
                    // A write to 0x2003 triggers the update of msu_data_addr...
                    //msu_data_addr <= {DIN, MSU_SEEK[23:0]};
                    // And a pulse of msu_data_seek.
                    //msu_data_seek <= 1'b1;
                end
                    // MSU_Track LSB
                16'h2004: begin
                    MSU_TRACK[7:0] <= DIN;
                end
                // MSU_Track MSB
                16'h2005: begin    
                    MSU_TRACK[15:8] <= DIN;
                    // Only update track_out when both (upper and lower) bytes arrive
                    track_out <= {DIN, MSU_TRACK[7:0]};
                end
                // MSU Audio Volume. (MSU_VOLUME).
                16'h2006: begin
                    MSU_VOLUME <= DIN;
                end
                // MSU Audio state control. (MSU_CONTROL).
                16'h2007: begin
                    // Writing to Audio State will do nothing if audio is already playing
                    msu_status_audio_playing_out <= DIN[0];
                    msu_status_audio_repeat <= DIN[1];
                    if (DIN[1] == 1) begin
                        // Pulse trig_play for only ONE clock cycle.
                        trig_play <= 1;
                    end
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
                // MSU_READ data
                16'h2001: begin
                    // if (!msu_status_data_busy) begin
                    //     // Data reads increase the memory address by 1
                    //     msu_data_addr <= msu_data_addr + 1;
                    // end
                    
                    //DOUT <= MSU_READ;
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
