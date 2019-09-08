//`define debug

module msu_audio(
  input clk,
  input reset,
  
  `ifndef debug
  input [31:0] img_size,
  input trig_play,
  input repeat_in,
  input trackmounting,
  input sd_buff_wr,
  input [15:0] sd_buff_dout,
  input [11:0] audio_fifo_usedw,
  input sd_ack_1,
  `endif
  
  // Used to tell sd card handling which LBA to jump to
  output reg [20:0] sd_lba_1,
  // Allows us to skip over samples when loop points are not on a sector boundary
  output reg ignore_sd_buffer_out,
  output reg audio_play,
  output reg [8:0] word_count,
  output reg [7:0] debug_here,
  output reg [31:0] loop_index,
  output reg sd_rd_1 // Needs to be wired to sd_rd[1] in consumer of this module
);

  `ifndef debug
  // Sector size is 512 bytes, so 256 words
  reg [8:0] sector_size_words = 9'd256;
  `endif
  
  `ifdef debug
  assign loop_index = 32'hf733;
  ///////////////////////////////////////////////
  // Debug testing
  // Assumed we are playing
  reg audio_play = 0;
  reg trig_play = 1;
  reg trackmounting_falling = 1;
  // Assumed image size
  //reg [31:0] img_size = 32'd8879616;
  reg [31:0] img_size = 32'd1040;
  // force repeating when high
  reg repeat_in = 0;
  
  reg sd_ack_1 = 0;
  reg sd_buff_wr = 1;
  reg [31:0] audio_fifo_usedw = 32'd0;
  // Typically this is 512 bytes
  reg [8:0] sector_size_words = 9'd64;
  reg ignore_sd_buffer_out = 0;
  ///////////////////////////////////////////////
  `endif

  reg [20:0] loop_frame;
  reg [8:0] loop_frame_word_offset;
  reg looping;
  reg [7:0] mode;
  reg [7:0] state;
  // End frame handling
  reg [20:0] end_frame;
  reg [8:0] end_frame_byte_offset;
  reg [8:0] end_frame_word_offset;
  reg [7:0] partial_frame_state;
  reg trackmounting_1;
  reg [20:0] current_frame;
  reg [20:0] max_end_frame;
   
  initial begin
  looping = 0;
  mode = 8'd0;
  state = 8'd0;
  // End frame handlingloop_index_in_words_full
  partial_frame_state = 8'd0;
  trackmounting_1 = 0;
  current_frame = 21'd0;
  max_end_frame = 21'd2097151;  
  debug_here = 8'd0;
  end_frame = 0;
  `ifndef debug
    loop_index = 32'd0;
  `endif
  end

  wire [31:0]img_size_frames = img_size >> 9;

  `ifndef debug
  // Work out trackmounting_falling
  wire trackmounting_falling = (trackmounting_1 && !trackmounting);
  `endif

  // Loop handling
  wire [31:0] loop_index_in_words_full = loop_index[31:0] << 1;
  wire [31:0] loop_index_in_frames_full = loop_index[31:0] >> 7;  
  
  always @(posedge clk) begin
    // We have a trigger to play...
    if (reset || trig_play) begin
      debug_here <= 8'd7;
      // Stop any existing audio playback
      current_frame <= 0;
      sd_lba_1 <= 0;
      state <= 0;
      audio_play <= 0;
      word_count <= 0;
      looping <= 0;
      partial_frame_state <= 0;
      end_frame <= 0;
      `ifndef debug
      loop_index <= 0;
      `endif
      
      end_frame_byte_offset <= 0;
      end_frame_word_offset <= 0;
      // Work out the audio playback mode
      if (!repeat_in) begin
        // Audio is not repeating and will stop
        // @todo force audio repeating for now
        mode <= 8'd2;
      end else begin
        // Audio is repeating
        mode <= 8'd2;
      end
      `ifdef debug
      sd_ack_1 <= 1'b1;
      trig_play <= 0;
      `endif
    end else begin
      `ifndef debug
      trackmounting_1 <= trackmounting;
      if (sd_ack_1 && sd_lba_1==0 && word_count==2 && sd_buff_wr) loop_index[15:0]  <= sd_buff_dout;
      if (sd_ack_1 && sd_lba_1==0 && word_count==3 && sd_buff_wr) loop_index[31:16] <= sd_buff_dout;
      if (sd_ack_1 && sd_lba_1==0 && word_count==4 && sd_buff_wr) begin
        // Now that we have the complete 8 byte header, we have a possible loop_index to handle
        loop_frame <= loop_index_in_frames_full[20:0];
        // Take the last 9 bits (512 byte sectors)
        loop_frame_word_offset <= loop_index_in_words_full[8:0] + 9'd2;
      end
      `endif
      
      case (state)
        0: begin
          // Audio track has finished mounting
          if (trackmounting_falling) begin
            debug_here <= 8'd6;
            // End frame calculations
            end_frame <= img_size_frames[20:0] - 1;
            end_frame_byte_offset <= img_size[8:0];
            end_frame_word_offset <= img_size[8:0] >> 1;
            looping <= 0;
            audio_play <= 1'b1;
            // Advance the SD card LBA and read in the next sector
            current_frame <= 21'd0;
            sd_lba_1 <= 21'd0;
            // Go! (request a sector from the HPS)
            sd_rd_1 <= 1'b1;
            state <= state + 1;
            `ifdef debug
            trackmounting_falling <= 0;
            `endif
          end
        end
        1: begin
          // Wait for ACK
          if (sd_ack_1) begin
            sd_rd_1 <= 1'b0;
            // sd_ack goes high at the start of a sector transfer (and during)
            word_count <= 0;
            state <= state + 1;
          end
        end
        2: begin
          // Keep collecting words until we hit the buffer limit 
          if (sd_ack_1 && sd_buff_wr) begin
            word_count <= word_count + 1;
            debug_here <= 8'd1;
            if (looping) begin
              // We may need to deal with some remainder samples after the loop frame
              if (word_count < loop_frame_word_offset) begin
                ignore_sd_buffer_out <= 1;
                debug_here <= 8'd2;
              end else begin
                looping <= 0;
                ignore_sd_buffer_out <= 0;
                debug_here <= 8'd3;
              end
            end
          end
          if (word_count == sector_size_words) begin
             word_count <= 0;
             `ifdef debug
             sd_ack_1 <= 0;
             `endif
          end
          if (partial_frame_state == 1 && word_count == end_frame_word_offset) begin
            word_count <= 0;
            partial_frame_state <= 2;
            debug_here <= 8'd4;
            `ifdef debug
            sd_ack_1 <= 0;
            `endif
          end
          // Only add new frames if we haven't filled the buffer
          if (!sd_ack_1 && audio_fifo_usedw < 1792) begin
            state <= state + 1;
            debug_here <= 8'd5;
          end
        end
        3: begin
          // Check if we've reached end_frame yet
          if ((current_frame < end_frame) && audio_play) begin
            // Nope, Fetch another frame
            current_frame <= current_frame + 1;
            sd_lba_1 <= sd_lba_1 + 1;
            sd_rd_1 <= 1'b1;
            state <= 1;
            debug_here <= 8'd8;
            `ifdef debug
            sd_ack_1 <= 1'b1;
            `endif
          end else begin
            // Deal with the end frame in the next state
            state <= state + 1;
            debug_here <= 8'd9;
          end
        end
        4: begin
          // Final frame handling
          if (audio_play && end_frame_byte_offset == 0) begin
            // Handle a full frame
            if (mode == 8'd1) begin
              // Full final frame, stopped
              audio_play <= 0;
              state <= 0;
              current_frame <= 0;
              sd_lba_1 <= 0;
              looping <= 0;
              debug_here <= 8'd10;
            end else begin
              // Full final frame, Looped
              current_frame <= loop_frame;
              sd_lba_1 <= loop_frame;
              sd_rd_1 <= 1'b1;
              state <= 1;
              looping <= 1;
              debug_here <= 8'd11;
              `ifdef debug
              sd_ack_1 <= 1'b1;
              `endif
            end
          end else begin
            case (partial_frame_state)
              0: begin
                // Move to the partial frame, which will be the last full frame + 1
                current_frame <= current_frame + 1;
                sd_lba_1 <= sd_lba_1 + 1;
                partial_frame_state <= 8'd1;
                debug_here <= 8'd12;
              end 
              1: begin
                // Keep reading bytes from the file for the partial frame
                sd_rd_1 <= 1'b1;
                state <= 1;
                debug_here <= 8'd13;
                `ifdef debug
                sd_ack_1 <= 1'b1;
                `endif
              end
              2: begin
                // We've reached the end of the partial frame now.. handle stopping/looping
                if (mode == 8'd1) begin
                  // Stopping
                  audio_play <= 0;
                  state <= 0;
                  sd_lba_1 <= 0;
                  partial_frame_state <= 0;
                  debug_here <= 8'd14;
                end else begin
                  // Loop
                  looping <= 1;
                  if (loop_frame == 0) begin
                    // Loop frame is zero, so just go back to 0
                    partial_frame_state <= 0;
                    current_frame <= 0;  
                    sd_lba_1 <= 0;
                    debug_here <= 8'd15;
                  end else begin
                    // Our loop point is a non-zero sample, go back to the loop frame first 
                    current_frame <= loop_frame;
                    sd_lba_1 <= loop_frame;
                    // We will deal with loop frame word offsets above
                    debug_here <= 8'd16;
                  end
                  word_count <= 0;
                  audio_play <= 1;
                  state <= 1;
                  sd_rd_1 <= 1'b1;
                  `ifdef debug
                  sd_ack_1 <= 1'b1;
                  `endif
                end
              end
            endcase
          end
        end 
        default:; // Do nothing but wait
      endcase
    end	
  end // Ends clocked block

endmodule