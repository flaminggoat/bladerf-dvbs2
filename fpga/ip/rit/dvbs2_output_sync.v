// Matthew Zachary
// Rochester Institute of Technology
// 7/18/2017
// Output Sync Block
// Synchronizes output of DVB transmitter system (after phyframer) to the output clock rate
//   by inserting dummy PL frames when there isn't enough data

// For IQ samples, a 'lookup' table has been used to reduce the bits/symbol from 12 (sc16q11 format) to 3 (for resource usage purposes)
// 3'h0 = 0x5a8
// 3'h7 = 0xa58
// 3'h1 = 0x7ba
// 3'h6 = 0x846
// 3'h2 = 0x212
// 3'h5 = 0xdee
// 3'h3 = 0x233
// 3'h4 = 0xdcd
// Reconversion is done in this block

module dvbs2_output_sync (clock_in, reset, enable, sym_i_in, sym_q_in, valid_in, output_clock, output_reset, done_out, fifo_wr_sel, sym_i_out, sym_q_out, valid_out, error, actual_out, fifo_switch_performed);
   // Inputs and Outputs
   input         clock_in; // Input clock. Write input data into FIFO at this rate.
   input         reset; // Synchronous reset
   input         enable; // Input enable
   input  [2:0]  sym_i_in; // I portion of input symbol
   input  [2:0]  sym_q_in; // Q portion of input symbol
   input         valid_in; // Raised if input symbol is valid (see if data is present)
   input 		 output_clock; // Output clock - based on symbol rate
   input 		 output_reset;
   input	     done_out;
   input		 fifo_wr_sel;
   output [11:0] sym_i_out; // I portion of output symbol
   output [11:0] sym_q_out; // Q portion of output symbol
   output        valid_out; // Raised if output symbol is valid
   output        error; // Raised if there is a FIFO error
   output        actual_out;
   output		 fifo_switch_performed;
	
   reg [11:0]    sym_i_out; // Register the I portion of the output symbol
   reg [11:0]    sym_q_out; // Register the Q portion of the output symbol

   // Related to the new output timing code
   // Signals that cross clock domains
   reg done_out_mff1;
   reg done_out_mff2;
   reg fifo_wr_sel_mff2;
   reg fifo_wr_sel_mff1;
   reg fifo_switch_performed;
	
   // output_clock
   reg fifo_rd_sel;
   reg valid_out;
   reg [11:0] dummy_counter;
   reg [14:0] frame_counter;
   reg [1:0] output_state;
   reg done_with_dummies;
   reg done_while_sending;
   reg fifo_new_rd_sel;
   reg fifo_read_rq;
   wire [5:0] sym_out_zero;
   wire [5:0] sym_out_one;
   wire fifo_zero_empty;
   wire fifo_zero_full;
   wire fifo_one_empty;
   wire fifo_one_full;
   reg actual_out;
   reg [3:0] src_sym_i_out;
   reg [3:0] src_sym_q_out;
   reg [2:0] dummy_sym_i_out;
   reg [2:0] dummy_sym_q_out;
   reg [1:0] data_source;

	// LFSR Signals
   reg [17:0] lfsr_x; // 18 bit LFSR for x sequence of PL scrambling
   reg [17:0] lfsr_y; // 18 bit LFSR for y sequence of PL scrambling
   reg        lfsr_en; // 1 bit signal to enable LFSR operation for the current clock cycle
   reg        lfsr_rst; // 1 bit signal to re-initialize the LFSR

   // Internal scrambling signals
   reg [1:0]  scramble_bits; // scramble bits calculated from LFSR for scrambling sequence
   reg        zna, znb; // 1 bit calculations from each LFSR to go toward calculating scramble_bits
	
   // Output state machine
   parameter [1:0] DUMMY_DATA_ACTUAL   = 2'b00;
   parameter [1:0] DUMMY_DATA_ZERO     = 2'b01;
   parameter [1:0] ACTUAL_DATA_ACTUAL  = 2'b10;
   parameter [1:0] ACTUAL_DATA_ZERO    = 2'b11;

   // Data sources
   parameter [1:0] ALL_ZERO = 2'b00;
   parameter [1:0] DUMMY 	= 2'b01;
   parameter [1:0] FIFO 	= 2'b10;

   assign error = fifo_zero_full | fifo_one_full;
	
   // Select the data source
   always @* begin
      case (data_source)
		 ALL_ZERO: begin
		    src_sym_i_out = 4'hf;
			src_sym_q_out = 4'hf;
		 end
		 DUMMY: begin
			src_sym_i_out = dummy_sym_i_out;
			src_sym_q_out = dummy_sym_q_out;
		 end
		 FIFO: begin
			if (fifo_rd_sel == 1'b1) begin
				src_sym_i_out = {1'b0, sym_out_one[2:0]};
				src_sym_q_out = {1'b0, sym_out_one[5:3]};
			end
			else begin
				src_sym_i_out = {1'b0, sym_out_zero[2:0]};
				src_sym_q_out = {1'b0, sym_out_zero[5:3]};
			end
		 end
		 default: begin
			src_sym_i_out = 4'hB;
			src_sym_q_out = 4'hB;
		 end
	  endcase
   end			

   // Convert our 4 digit code to full i/q samples
   always @* begin
      case(src_sym_i_out)
         0: begin
            sym_i_out = 12'h5a8; //32'h3f3504f3;
         end
         1: begin
            sym_i_out = 12'h7ba; //32'h3f7746ea;
         end
         2: begin
            sym_i_out = 12'h212; //32'h3e8483ee;
         end
         3: begin
            sym_i_out = 12'h233; //32'h3e8cdeff;
         end
         4: begin
            sym_i_out = 12'hdcd; //32'hbe8cdeff;
         end
         5: begin
            sym_i_out = 12'hdee; //32'hbe8483ee;
         end
         6: begin
            sym_i_out = 12'h846; //32'hbf7746ea;
         end
         7: begin
            sym_i_out = 12'ha58; //32'hbf3504f3;
         end
		 15: begin
            sym_i_out = 12'h000; //Zero;
         end
         default: begin
            sym_i_out = 12'hBEF;
         end
      endcase // dummy_sym_i_out
   end

   // Convert our 4 digit code to full i/q samples
   always @* begin
      case(src_sym_q_out)
         0: begin
            sym_q_out = 12'h5a8; //32'h3f3504f3;
         end
         1: begin
            sym_q_out = 12'h7ba; //32'h3f7746ea;
         end
         2: begin
            sym_q_out = 12'h212; //32'h3e8483ee;
         end
         3: begin
            sym_q_out = 12'h233; //32'h3e8cdeff;
         end
         4: begin
            sym_q_out = 12'hdcd; //32'hbe8cdeff;
         end
         5: begin
            sym_q_out = 12'hdee; //32'hbe8483ee;
         end
         6: begin
            sym_q_out = 12'h846; //32'hbf7746ea;
         end
         7: begin
            sym_q_out = 12'ha58; //32'hbf3504f3;
         end
		 15: begin
            sym_q_out = 12'h000; //Zero;
         end
         default: begin
            sym_q_out = 12'hBEF;
		 end
      endcase // dummy_sym_q_out
   end
	
   // LFSR for PL scrambling
   always @(negedge output_clock, posedge output_reset) begin
      if (output_reset) begin // if reset
         lfsr_x <= 18'h00001; // initialize x(0) = 1, x(1)=x(2)=...=x(17)=0
         lfsr_y <= 18'h3FFFF; // initialize y(0)=y(1)=...=y(17)=1
      end // if reset
      else begin // else not reset
         if (lfsr_rst) begin // LFSR should be re-initalized for each frame
            lfsr_x <= 18'h00001; // initialize x(0) = 1, x(1)=x(2)=...=x(17)=0
            lfsr_y <= 18'h3FFFF; // initialize y(0)=y(1)=...=y(17)=1
         end // if lfsr_rst
         else begin
            if (lfsr_en) begin // only operate this clock cycle if LFSR is enabled by state machine
               lfsr_x <= {lfsr_x[7]^lfsr_x[0],lfsr_x[17:1]}; // x^7 + 1
               lfsr_y <= {lfsr_y[10]^lfsr_y[7]^lfsr_y[5]^lfsr_y[0],lfsr_y[17:1]}; // y^10 + y^7 + y^5 + 1
            end // if lfsr_en
            else begin // else keep LFSR contents the same
               lfsr_x <= lfsr_x;
               lfsr_y <= lfsr_y;
            end // else not lfsr_en
         end // else not lfsr_rst
      end // else not reset
   end // LFSR for PL scrambling
	
   // Making sure we always output 
   always @(posedge output_clock, posedge output_reset) begin
		if (output_reset) begin
			done_out_mff1 <= 1'b0;
			done_out_mff2 <= 1'b0;
			fifo_wr_sel_mff1 <= 1'b0;
			fifo_wr_sel_mff2 <= 1'b0;

			fifo_rd_sel <= 1'b1;
            fifo_new_rd_sel <= 1'b0;
            done_while_sending <= 1'b0;
			valid_out <= 1'b0;
		    fifo_read_rq <= 1'b0;
			dummy_sym_i_out <= 3'b0;
			dummy_sym_q_out <= 3'b0;
			data_source <= ALL_ZERO;
			fifo_switch_performed <= 1'b0;
			
			dummy_counter <= 12'b0;
			frame_counter <= 15'b0;
			done_with_dummies <= 1'b0;
			output_state <= DUMMY_DATA_ACTUAL;
            actual_out <= 1'b0;
			
			lfsr_rst <= 1'b1;
			lfsr_en <= 1'b0;
			scramble_bits = 2'b00;
            zna = 1'b0;
            znb = 1'b0;
		end
		else begin
			// Cross the clock domain
			done_out_mff2 <= done_out_mff1;
			done_out_mff1 <= done_out;
			fifo_wr_sel_mff2 <= fifo_wr_sel_mff1;
			fifo_wr_sel_mff1 <= fifo_wr_sel;

			case (output_state)
			    // Dummy frame symbols
			    DUMMY_DATA_ACTUAL: begin
               		// If the done flag was thrown while we're doing a dummy frame
              		if ((done_out_mff2 == 1'b1) & (done_while_sending == 1'b0)) begin
                  		// Set flags
                 		done_while_sending <= 1'b1;
                  		fifo_switch_performed <= 1'b1;

                  		// Store this for later
                  		fifo_new_rd_sel <= fifo_wr_sel_mff2;
               		end
					
					// Select the data source for the output
					data_source <= DUMMY;
					
   					// look up header value to output
					case (dummy_counter)
						// Start with your typical header
						0: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h0; 
						end
						1: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h7;
						end
						2: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7; 
						end
						3: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						4: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						5: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						6: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7; 
						end
						7: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7; 
						end
						8: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h0; 
						end
						9: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h7; 
						end
						10: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h0; 
						end
						11: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						12: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h7; 
						end
						13: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						14: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h7; 
						end
						15: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h7; 
						end
						16: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h7; 
						end
						17: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						18: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h7; 
						end
						19: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						20: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h0; 
						end
						21: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						22: begin
							dummy_sym_i_out <= 3'h0; 
							dummy_sym_q_out <= 3'h0; 
						end
						23: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						24: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h7; 
						end
						25: begin
							dummy_sym_i_out <= 3'h7; 
							dummy_sym_q_out <= 3'h0; 
						end
						26: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						27: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						28: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						29: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						30: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						31: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						32: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						33: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						34: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						35: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						36: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						37: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						38: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						39: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						40: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						41: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						42: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						43: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						44: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						45: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						46: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						47: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						48: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						49: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						50: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						51: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						52: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						53: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						54: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						55: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						56: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						57: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						58: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						59: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						60: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						61: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						62: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						63: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						64: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						65: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						66: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						67: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						68: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						69: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						70: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						71: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						72: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						73: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						74: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						75: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						76: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						77: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						78: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						79: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						80: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h0;
						end
						81: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						82: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						83: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						84: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						85: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h0;
						end
						86: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						87: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						88: begin
							dummy_sym_i_out <= 3'h7;
							dummy_sym_q_out <= 3'h7;
						end
						89: begin
							dummy_sym_i_out <= 3'h0;
							dummy_sym_q_out <= 3'h7;
						end
						default: begin
							// Calculate scramble bits based on LFSR
							zna = lfsr_x[0]^lfsr_y[0];
							znb = (lfsr_y[15]^lfsr_y[14]^lfsr_y[13]^lfsr_y[12]^lfsr_y[11]^lfsr_y[10]^lfsr_y[9]^lfsr_y[8]^lfsr_y[6]^lfsr_y[5]) ^ (lfsr_x[15]^lfsr_x[6]^lfsr_x[4]); // 0xFF60 and 0x8050 generator polynomials
							scramble_bits = {znb,1'b0} + {1'b0,zna}; // rn = 2*znb + zna (shift znb left by 1 to multiply by 2)

							// Decide how to modify (scramble) pilot symbol based on scrambling sequence term from LFSR
							case (scramble_bits)
								2'b00: begin // No change to input symbol
									dummy_sym_i_out <= 3'h0;
									dummy_sym_q_out <= 3'h0;
								end
								2'b01: begin // Swap symbols and change the sign of the Q symbol
									dummy_sym_i_out <= 3'h7; //not
									dummy_sym_q_out <= 3'h0;
								end
								2'b10: begin // Change the signs of both symbols
									dummy_sym_i_out <= 3'h7; //not
									dummy_sym_q_out <= 3'h7; //not
								end
								2'b11: begin // Swap symbols and change the sign of the I symbol
									dummy_sym_i_out <= 3'h0;
									dummy_sym_q_out <= 3'h7; //not
								end
							endcase // scramble_bits case
						end
					endcase // header_index case
					
					// Hold the output data for 2 clock cycles
					if (valid_out == 1'b0) begin
						valid_out <= 1'b1;
						
						// Special case
						// End of frame
						if (dummy_counter == 3401) begin
							// Done with this dummy frame
							done_with_dummies <= 1'b1;
						end
					end
					else begin
						// Special case
						// End of header
						if (dummy_counter == 89) begin
							// Reset, start cycling
							lfsr_rst <= 1'b1;
							lfsr_en <= 1'b0;
						end
						else begin
							// Perform 1 cycle
							lfsr_en <= 1'b1;
						end
						
						valid_out <= 1'b0;
						output_state <= DUMMY_DATA_ZERO;
						dummy_counter <= dummy_counter + 1'b1;
					end
					
               		actual_out <= 1'b0;
				end // DUMMY_DATA_ACTUAL
				// Zeroes in between dummy symbols
				DUMMY_DATA_ZERO: begin
					// Hold the LFSR data
					lfsr_en <= 1'b0;
					lfsr_rst <= 1'b0;
					
					// Select the data source
					data_source <= ALL_ZERO;

					// Hold the output data for 2 clock cycles
					if (valid_out == 1'b0) begin
						valid_out <= 1'b1;
					end
					else begin
						valid_out <= 1'b0;
						
						// Reset
						if (done_with_dummies == 1'b1) begin
	   						dummy_counter <= 12'b0;
	   						done_with_dummies <= 1'b0;
						end 
						
						// If we're done with dummies and there's data available
	   					if ((done_with_dummies == 1'b1) & ((done_out_mff2 == 1'b1) | (done_while_sending == 1'b1))) begin
	   						// Indicate we switched FIFOs to read
                     		// Don't set the flag if it was already sent
                     		if (done_while_sending == 1'b0) begin
	   					   		fifo_switch_performed <= 1'b1;

                        		// Read from the previously read FIFO
                        		fifo_rd_sel <= fifo_wr_sel_mff2;
                     		end
	                     	else begin
	                       		// Read from the previously read FIFO
	                        	fifo_rd_sel <= fifo_new_rd_sel;
	                     	end

	                     	// On to actual data :)
		   					output_state <= ACTUAL_DATA_ACTUAL;
	                     	actual_out <= 1'b0;

		   					// Prepare for data output
		   					fifo_read_rq <= 1'b1;

		   					// Reset
	                     	done_while_sending <= 1'b0;
	   					end
	   					// Anoher dummy vector
	   					else begin
	   						output_state <= DUMMY_DATA_ACTUAL;
		   				end // done
                	end // valid
   				end // DUMMY_DATA_ZERO
				// Actual data
				ACTUAL_DATA_ACTUAL: begin
	   				//Reset the switch performed flag
	   				if (done_out_mff2 == 1'b0) begin
	   					fifo_switch_performed <= 1'b0;
	   				end

					// Select the data source
					data_source <= FIFO;

					// Reset
	   				fifo_read_rq <= 1'b0;

		   			// Hold the output data for 2 clock cycles
	   				if (valid_out == 1'b0) begin
	   					valid_out <= 1'b1;
	                  	actual_out <= 1'b1;
	   				end
	   				else begin
	   					valid_out <= 1'b0;
	   					output_state <= ACTUAL_DATA_ZERO;
	                  	actual_out <= 1'b0;
	   				end
				end // ACTUAL_DATA_ACTUAL
				// Zeroes in between actual data
				ACTUAL_DATA_ZERO: begin					
					//Reset the switch performed flag
   					if (done_out_mff2 == 1'b0) begin
   						fifo_switch_performed <= 1'b0;
   					end

					// Select the data source
					data_source <= ALL_ZERO;
					
					// Reset
					fifo_read_rq <= 1'b0;
               		actual_out <= 1'b0;

	   				// Hold the output data for 2 clock cycles
	   				if (valid_out == 1'b0) begin
	   					valid_out <= 1'b1;
	   				end
	   				else begin
	   					valid_out <= 1'b0;

	   					// See if we're done
	   					// Each Frame has 16686 symbols
	   					if (frame_counter == 16685) begin
	   						frame_counter <= 14'b0;
	   						
	   						// If there's data available
		   					if (done_out_mff2 == 1'b1) begin
		   						// Read from the previously read FIFO
			   					fifo_rd_sel <= fifo_wr_sel_mff2;

			   					// Indicate we switched FIFOs to read
			   					fifo_switch_performed <= 1'b1;
			   					output_state <= ACTUAL_DATA_ACTUAL;

			   					// Prepare for data output
			   					fifo_read_rq <= 1'b1;
		   					end
		   					// Anoher dummy vector
		   					else begin
		   						output_state <= DUMMY_DATA_ACTUAL;
		   					end
	   					end
	   					else begin
	   						frame_counter <= frame_counter + 1'b1;

							// Prepare for data output
			   				fifo_read_rq <= 1'b1;
							output_state <= ACTUAL_DATA_ACTUAL;
	   					end
	   				end
				end // ACTUAL_DATA_ZERO
			endcase // Output state machine
		end // if reset
   end // always loop

   // Store data in FIFO to account for irregular valid_out signals
   // Store both I and Q samples in the same FIFO
   // {q,i}
   // FIFO zero - alternates between this and FIFO one
   output_fifo_6bit_dual_clk_15bit sym_out_fifo_zero (
	   .data    ({sym_q_in[2:0], sym_i_in[2:0]}),
	   .rdclk   (output_clock),
	   .rdreq   (fifo_read_rq & ~fifo_rd_sel),
	   .wrclk   (clock_in),
	   .wrreq   (valid_in & ~fifo_wr_sel),
	   .q       (sym_out_zero),
	   .rdempty (fifo_zero_empty), // Empty signal from the read side of the FIFO
	   .wrfull  (fifo_zero_full) // Full signal from the write side of the FIFO
   );
	
   // Store data in FIFO to account for irregular valid_out signals
   // Store both I and Q samples in the same FIFO
   // {q,i}
   // FIFO one - alternates between this and FIFO zero
   output_fifo_6bit_dual_clk_15bit sym_out_fifo_one (
      .data    ({sym_q_in[2:0], sym_i_in[2:0]}),
      .rdclk   (output_clock),
      .rdreq   (fifo_read_rq & fifo_rd_sel),
      .wrclk   (clock_in),
      .wrreq   (valid_in & fifo_wr_sel),
      .q       (sym_out_one),
      .rdempty (fifo_one_empty), // Empty signal from the read side of the FIFO
      .wrfull  (fifo_one_full) // Full signal from the write side of the FIFO
   );

endmodule // dvbs2_output_sync