module msu(
  input clk,
  input reset,

  input [31:0] img_size,
  input trig_play,
  input trig_pause,
  input repeat_in,
  input trackmounting,
  input trackmissing,
  input trackfinished,
  input [11:0] audio_fifo_usedw,
  input audio_play_in,

  output reg audio_play,
  output reg [8:0] word_count,
  output reg trackmissing_reset
);

  // TODO Should no longer be a frame
  reg [8:0] loop_frame_word_offset;
  reg looping;

  initial begin
  looping = 0;
  state = 8'd0;
  loop_index = 32'd0;
  trackmissing_reset = 0;
  end

  localparam WAITING_FOR_PLAY_STATE = 8'd0;
  localparam WAITING_SD_STATE = 8'd1;
  localparam PLAYING_STATE = 8'd2;
  localparam PLAYING_CHECKS_STATE = 8'd3;
  localparam FINAL_FRAME_STATE = 8'd4;
  localparam PAUSED_STATE = 8'd5;


  // Loop handling
  wire [31:0] loop_index_in_words_full = loop_index[31:0] << 1;

  reg just_reset = 0;
  reg trackmissing_1 = 1'b1;
  reg [7:0] state;

  always @(posedge clk) begin
    if (reset || trackmounting || trackmissing_reset) begin
      // Stop any existing audio playback
      audio_play <= 0;

      current_word <= 0;
      state <= 0;
      word_count <= 0;
      end_word <= 0;
      looping <= 0;
      loop_index <= 0;
      trackmissing_reset <= 0;

      // Pulse just_reset
      just_reset <= 1;
    end else begin
      just_reset <= 0;

      // Trackmissing handling
      trackmissing_1 <= trackmissing;
      if (trackmissing && !just_reset) begin
        // We need to reset audio file playing on trackmissing, but only once
        trackmissing_reset <= 1;
      end

      // Falling edge of trackmissing needs to set things up for another potential trackmissing
      if (trackmissing_1 && trackmissing) begin
        trackmissing_reset <= 0;
        trackmissing_1 <= 1;
      end

      // TODO this needs to use EXT stuff
      if (sd_ack_1 && sd_lba_1==0 && word_count==2 && sd_buff_wr) begin
        // loop_index[15:0]  <= sd_buff_dout;
      end
      if (sd_ack_1 && sd_lba_1==0 && word_count==3 && sd_buff_wr) loop_index[31:16] <= sd_buff_dout;
      if (sd_ack_1 && sd_lba_1==0 && word_count==4 && sd_buff_wr) begin
        // Now that we have the complete 8 byte header, we have a possible loop_index to handle
        loop_frame <= loop_index_in_frames_full[20:0];
        // Take the last 9 bits (512 byte sectors, 256 words)
        loop_frame_word_offset <= loop_index_in_words_full[7:0] + 9'd2;
      end
      case (state)
        WAITING_FOR_PLAY_STATE: begin
          if (trig_play) begin
            current_word <= 0;
            word_count <= 0;
            state <= 0;
            looping <= 0;
            just_reset <= 0;
            // Go! (request to play the selected track via EXT)
            audio_play <= 1;
            sd_rd_1 <= 1;
            state <= WAITING_SD_STATE;
          end
        end
        WAITING_SD_STATE: begin
          if (sd_ack_1) begin
            debug_here <= 8'd1;
            // Wait for ACK
            sd_rd_1 <= 1'b0;
            // sd_ack goes high at the start of a sector transfer (and during)
            word_count <= 0;
            state <= PLAYING_STATE;
          end
        end
        PLAYING_STATE: begin
          if (trig_pause) begin
            audio_play <= 0;
            state <= PAUSED_STATE;
          end else begin
            // Keep collecting words until we hit the buffer limit
            if (sd_ack_1 && sd_buff_wr) begin
              debug_here <= 8'd3;
              word_count <= word_count + 1;
              if (looping) begin
                // We may need to deal with some remainder samples after the loop frame
                if (word_count < loop_frame_word_offset) begin
                  debug_here <= 8'd4;
                  ignore_sd_buffer_out <= 1;
                end else begin
                  debug_here <= 8'd5;
                  looping <= 0;
                  ignore_sd_buffer_out <= 0;
                end
              end
            end
            if (word_count == sector_size_words) begin
              word_count <= 0;
            end
            if (partial_frame_state == 1 && word_count == end_frame_word_offset) begin
              debug_here <= 8'd6;
              word_count <= 0;
              partial_frame_state <= 2;
            end
            // Only add new frames if we haven't filled the buffer
            if (!sd_ack_1 && audio_fifo_usedw < 1792) begin
              state <= PLAYING_CHECKS_STATE;
            end
          end
        end
        PLAYING_CHECKS_STATE: begin
          // Check if we've reached end_frame yet
          if ((current_frame < end_frame) && audio_play) begin
            // Nope, Fetch another frame
            current_frame <= current_frame + 1;
            sd_lba_1 <= sd_lba_1 + 1;
            sd_rd_1 <= 1'b1;
            state <= WAITING_SD_STATE;
          end else begin
            // Deal with the end frame in the next state
            state <= FINAL_FRAME_STATE;
          end
        end
        FINAL_FRAME_STATE: begin
          // Final frame handling
          if (audio_play && end_frame_byte_offset == 0) begin
            // Handle a full frame
            if (!repeat_in) begin
              debug_here <= 8'd7;
              // Full final frame, stopped
              audio_play <= 0;
              state <= 0;
              current_frame <= 0;
              sd_lba_1 <= 0;
              looping <= 0;
            end else begin
              debug_here <= 8'd8;
              // Full final frame, Looped
              current_frame <= loop_frame;
              sd_lba_1 <= loop_frame;
              sd_rd_1 <= 1'b1;
              state <= 1;
              looping <= 1;
            end
          end else begin
            case (partial_frame_state)
              0: begin
                // Move to the partial frame, which will be the last full frame + 1
                current_frame <= current_frame + 1;
                sd_lba_1 <= sd_lba_1 + 1;
                partial_frame_state <= 8'd1;
              end
              1: begin
                // Keep reading bytes from the file for the partial frame
                sd_rd_1 <= 1'b1;
                state <= 1;
              end
              2: begin
                // We've reached the end of the partial frame now.. handle stopping/looping
                if (!repeat_in) begin
                  debug_here <= 8'd9;
                  // Stopping
                  audio_play <= 0;
                  state <= WAITING_FOR_PLAY_STATE;
                  sd_lba_1 <= 0;
                  partial_frame_state <= 0;
                end else begin
                  // Loop
                  looping <= 1;
                  if (loop_frame == 0) begin
                    debug_here <= 8'd10;
                    // Loop frame is zero, so just go back to 0
                    partial_frame_state <= 0;
                    current_frame <= 0;
                    sd_lba_1 <= 0;
                  end else begin
                    debug_here <= 8'd11;
                    // Our loop point is a non-zero one, go back to the loop frame next
                    current_frame <= loop_frame;
                    sd_lba_1 <= loop_frame;
                    // We will deal with loop frame word offsets above
                  end
                  word_count <= 0;
                  audio_play <= 1;
                  state <= WAITING_SD_STATE;
                  sd_rd_1 <= 1'b1;
                end
              end
            endcase
          end
        end
        PAUSED_STATE: begin
          if (trig_play) begin
            audio_play <= 1;
            sd_rd_1 <= 1'b1;
            state <= PLAYING_STATE;
          end
        end
        default:; // Do nothing but wait
      endcase
    end
  end // Ends clocked block

endmodule