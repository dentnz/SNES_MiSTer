module MSU(
    input CLK,

    input ENABLE,
    input RD_N,
    input WR_N,
    input RST_N,

    input      [23:0] ADDR,
    input       [7:0] DIN,
    output reg  [7:0] DOUT,

    // Audio HPS control
    output     [31:0] addr_out,
(*keep*) output reg [15:0] track_out,
    input             track_mounting,
    input             track_finished,

    // Audio player control
    output reg        trig_play,
    output reg        trig_pause,
    output reg  [7:0] volume_out,

    output reg msu_status_audio_busy,
    output reg msu_status_audio_repeat,
    // This should contain if the msu_audio instance is currently playing
    input  reg msu_status_audio_playing_in,
    // This should output play/stop coming from game code poking MSU_CONTROL 
    output reg msu_status_audio_playing_out,
    // Track missing will be pulsed from hps_io
    input      msu_status_track_missing_in,
    output reg msu_status_track_missing,
    
    output reg [31:0] msu_data_addr = 0,
    input [7:0] msu_data_in,
    input msu_status_data_busy,
    output reg msu_data_seek,
    output reg [7:0] dbg_msu_reg,
    output reg [7:0] dbg_msu_status
);

initial begin
    msu_status_audio_busy = 0;
    msu_status_audio_repeat = 0;
    msu_status_audio_playing_out = 0;
    msu_status_track_missing = 0;
    msu_data_addr = 0;
    track_out = 0;
    trig_play = 0;
    trig_pause = 0;
    dbg_msu_reg = 0;
    track_mounting_falling = 0;
    track_mounting_old = 0;
    track_mounting_falling_old = 0;
    track_mounting_falling_rising = 0;
    track_change_audio_busy = 0;
end

assign volume_out = MSU_VOLUME;

// Read 'registers'
// MSU_STATUS - $2000
// Status bits
localparam [2:0] msu_status_revision = 3'b001;
wire [7:0] MSU_STATUS = {
    msu_status_data_busy, 
    msu_status_audio_busy, 
    msu_status_audio_repeat, 
    msu_status_audio_playing_out, 
    msu_status_track_missing, 
    msu_status_revision
};

assign dbg_msu_status = MSU_STATUS;

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
// THIS ISN'T RIGHT!! Busy bit should be set on write to $2005 IMMEDIATELY
// assign msu_status_audio_busy = track_mounting;

// Make sure we are aware of which bank ADDR is currently in 
(*keep*) wire IO_BANK_SEL = (ADDR[23:16]>=8'h00 && ADDR[23:16]<=8'h3F) || (ADDR[23:16]>=8'h80 && ADDR[23:16]<=8'hBF);

// Rising and falling edge detection
reg RD_N_1 = 1'b1;
reg WR_N_1 = 1'b1;
reg msu_status_track_missing_in_1 = 1'b1;

// track mounting with respect to audio busy
reg track_mounting_falling = 0;
reg track_mounting_old = 0;
reg track_mounting_falling_old = 0;
reg track_mounting_falling_rising = 0;
reg track_change_audio_busy = 0;

always @(posedge CLK or negedge RST_N) begin
    if (~RST_N) begin
        // Handle RESET
        MSU_SEEK <= 0;
        MSU_TRACK <= 16'h0000;
        track_out <= 16'h0000;
        MSU_VOLUME <= 0;
        MSU_CONTROL <= 0;
        msu_status_audio_playing_out <= 0;
        msu_status_audio_repeat <= 0;
        msu_status_track_missing <= 0;
        msu_status_track_missing_in_1 <= 1;
        RD_N_1 = 1;
        WR_N_1 = 1;
        DOUT <= 0;
        trig_play <= 0;
        trig_pause <= 0;
        msu_data_seek <= 0;
        msu_data_addr <= 32'h00000000;

        track_mounting_old <= 0;
        track_mounting_falling_old <= 0;
        track_change_audio_busy <= 0;
    end else begin
        // Reset our play triggers for pulsing
        trig_play <= 0;
        trig_pause <= 0;
        msu_data_seek <= 0;

        // Rising and falling edge detection stuff
        RD_N_1 <= RD_N;
        WR_N_1 <= WR_N;
        msu_status_track_missing_in_1 <= msu_status_track_missing_in;
        track_mounting_old <= track_mounting;

        // Status reads... this could go back in our read block below
        // if (ENABLE && IO_BANK_SEL && ADDR[15:0]==16'h2000 && (!RD_N_1 && RD_N) ) begin
        //     DOUT <= MSU_STATUS;
        //     dbg_msu_reg <= 8'd1;
        // end

        // Falling edge of track mounting
        if (track_mounting_falling) begin
            dbg_msu_reg <= 8'd7;
            msu_status_track_missing <= msu_status_track_missing_in;
            track_change_audio_busy <= 0;
        end

        // RISING edge of RD_N, when it goes to idle
        // So the address increments AFTER the SNES has read the data from the CURRENT address.
        // 0x2001 = MSU DATA Port.
        // if (ENABLE && IO_BANK_SEL && ADDR[15:0]==16'h2001 && (!RD_N_1 && RD_N) ) begin
        //     msu_data_addr <= msu_data_addr + 1;
        // end

        // FALLING edge of WR_N.
        // 0x2003 = MSU SEEK Port
        // if (ENABLE && IO_BANK_SEL && ADDR[15:0]==16'h2003 && (WR_N_1 && !WR_N) ) begin
        //     // A write to 0x2003 triggers the update of msu_data_addr...
        //     msu_data_addr <= {DIN, MSU_SEEK[23:0]};
        //     // And a SINGLE clock pulse of msu_data_seek
        //     msu_data_seek <= 1'b1;
        // end
        
        // FALLING edge of WR_N.
        // 0x2007 = MSU CONTROL
        // @todo is this needed any more?
        // ********************************************* TRY TO REMOVE THIS AGAIN!!!
        // if (ENABLE && IO_BANK_SEL && ADDR[15:0] == 16'h2007 && (WR_N_1 && !WR_N)) begin
        //     dbg_msu_reg <= 8'd13;
        //     if (!msu_status_audio_busy) begin
        //         msu_status_audio_repeat <= DIN[1];
        //         // We can only play/pause a track that has been set
        //         if (MSU_TRACK != 16'h0000 && !msu_status_track_missing) begin
        //             msu_status_audio_playing_out <= DIN[0];
        //             if (DIN[0] == 1) begin
        //                 // Pulse trig_play for only ONE clock cycle
        //                 trig_play <= 1;
        //                 dbg_msu_reg <= 8'd2;    
        //             end else if (DIN[0] == 0) begin
        //                 // Pulse trig_pause for only ONE clock cycle
        //                 trig_pause <= 1;
        //                 dbg_msu_reg <= 8'd3;
        //             end
        //         end
        //     end
        // end

        // @todo this might not be needed here
        // if (track_finished) begin
        //     msu_status_audio_playing_out <= 0;
        // end

        // @todo maybe Track mounting should be the check here 

        // Track missing is rising
        if (!msu_status_track_missing_in_1 && msu_status_track_missing_in) begin
            // Status bit set (see $2005 for where it gets unset)
            msu_status_track_missing <= 1;
            track_change_audio_busy <= 0;
            dbg_msu_reg <= 8'd9;
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
                    dbg_msu_reg <= 8'd11;    
                    MSU_TRACK[15:8] <= DIN;
                    // Only update track_out when both (upper and lower) bytes arrive
                    track_out <= {DIN, MSU_TRACK[7:0]};
                    msu_status_track_missing <= 0;
                    // Busy bit goes high immediately after track is set
                    track_change_audio_busy <= 1;
                end
                // MSU Audio Volume. (MSU_VOLUME).
                16'h2006: begin
                    MSU_VOLUME <= DIN;
                end
                // MSU Audio state control. (MSU_CONTROL).
                16'h2007: begin
                    dbg_msu_reg <= 8'd12;
                    if (!msu_status_audio_busy) begin
                        msu_status_audio_repeat <= DIN[1];
                        // We can only play/pause a track that has been set, and not on a missing track either
                        if (MSU_TRACK != 16'h0000 && !msu_status_track_missing) begin
                            msu_status_audio_playing_out <= DIN[0];
                            if (DIN[0] == 1) begin
                                // Pulse trig_play for only ONE clock cycle
                                trig_play <= 1;    
                            end else if (DIN[0] == 0) begin
                                // Pulse trig_pause for only ONE clock cycle
                                trig_pause <= 1;
                            end
                        end
                    end
                end
                default:;
            endcase
        end 
        //end else if (ENABLE & ~RD_N & IO_BANK_SEL) begin
        if (ENABLE & ~RD_N & IO_BANK_SEL) begin
        // Register reads
            case (ADDR[15:0])
                 // MSU_STATUS
                16'h2000: begin
                    dbg_msu_reg <= 8'd10;
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

assign track_mounting_falling = !track_mounting & track_mounting_old;
assign track_mounting_falling_rising = track_mounting_falling & !track_mounting_falling_old;
// Audio busy should happen immediately on track selection, and stop immediately after track is mounted
assign msu_status_audio_busy = (track_change_audio_busy || track_mounting) && !track_mounting_falling_rising;  

endmodule
