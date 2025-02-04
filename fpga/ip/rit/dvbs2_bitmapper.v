// Maps 4 bit groupings of FECFRAME and outputs IQ symbols in XFECFRAME
// 64800 bits into this block in series, every 4 bits collected & mapped to IQ symbol, output 16200 symbols
// output IQ symbol bits in parallel, so output is 1/4 rate of input

// For IQ samples, a 'lookup' table has been used to reduce the bits/symbol from 12 (sc16q11 format) to 3 (for resource usage purposes)
// 3'h0 = 0x5a8
// 3'h7 = 0xa58
// 3'h1 = 0x7ba
// 3'h6 = 0x846
// 3'h2 = 0x212
// 3'h5 = 0xdee
// 3'h3 = 0x233
// 3'h4 = 0xdcd
// Reconversion is done in the dvbs2_output_sync block

module dvbs2_bitmapper (clock_in, reset, enable, bit_in, clock_out, valid_in, sym_i, sym_q, valid_out);
   // Inputs and Outputs
   input         clock_in;
   input         reset;
   input         enable;
   input         bit_in;
   input         clock_out; // output clock of 1/4 the rate of input clock
   input         valid_in;
   output [2:0] sym_i;
   output [2:0] sym_q;
   output        valid_out;

   // Register outputs
   reg [2:0] sym_i;
   reg [2:0] sym_q;
   reg        valid_out;

   // Need to collect 4 input bits to output a symbol
   //    These are clocked in the faster clock domain (clock_in)
   reg [1:0] bit_cnt; // input bit counter
   reg [3:0] collected_input;
   reg [3:0] final_collected_input; // register collected_input once done collecting 4 bits
   reg       final_collected_valid; // signals whether or not final_collected_input is valid to second clock domain

   // Double register these since crossing clock domains
   //    These are clocked in the slower clock domain (clock_out)
   reg [3:0] collected_input_reg1;
   reg [3:0] collected_input_reg2;
   reg       collected_valid_reg1;
   reg       collected_valid_reg2;

   // Keep track if haven't had valid data in a while
   reg [1:0] not_valid_count;

   // Collect every 4 input bits
   always @(posedge clock_in, posedge reset) begin
      if (reset) begin // if reset
         bit_cnt               <= 2'b00;
         collected_input       <= 4'h0;
         final_collected_input <= 4'h0;
         final_collected_valid <= 1'b0;
         not_valid_count       <= 2'b00;
      end // if reset
      else begin // else not reset
         final_collected_input <= final_collected_input; // by default
         final_collected_valid <= final_collected_valid; // by default
         if (valid_in) begin // only operate if have valid input bit
            bit_cnt <= bit_cnt + 2'b01; // increment counter (it rolls over when done)

            // Shift input bits through the 4 bit register to capture them
            if (bit_cnt == 2'b00) begin
               collected_input <= {3'b000,bit_in}; 
            end
            else if (bit_cnt == 2'b11) begin
               collected_input       <= {collected_input[2:0],bit_in};
               final_collected_input <= {collected_input[2:0],bit_in};
               final_collected_valid <= 1'b1;
            end
            else begin
               collected_input <= {collected_input[2:0],bit_in};
            end
         end // if valid_in
         else begin
            bit_cnt         <= bit_cnt;
            collected_input <= collected_input;
            not_valid_count <= not_valid_count + 2'b01; // increment counter

            if (not_valid_count == 2'b11) begin
               final_collected_valid <= 1'b0; // final_collected_input no longer valid since have had invalid input for a while
            end
         end
      end // else not reset
   end // collect input bits always

   // Main Functionality
   always @(posedge clock_out, posedge reset) begin
      if (reset) begin // if reset
         sym_i                <= 3'h0;
         sym_q                <= 3'h0;
         valid_out            <= 1'b0;
         collected_input_reg1 <= 4'h0;
         collected_input_reg2 <= 4'h0;
         collected_valid_reg1 <= 1'b0;
         collected_valid_reg2 <= 1'b0;
      end // if reset
      else begin // else not reset
         // Double register for clock domain crossing
         collected_input_reg2 <= collected_input_reg1;
         collected_input_reg1 <= final_collected_input;
         collected_valid_reg2 <= collected_valid_reg1;
         collected_valid_reg1 <= final_collected_valid;

         if (enable) begin // only operate when enabled
            // Process the collected 4 bits
            if (collected_valid_reg2) begin
               valid_out     <= 1'b1;
               // Bit Mapper Look-up Values
               // For normal FECFRAME size (64800 bits), 16APSK modulation, 9/10 code rate
               case (collected_input_reg2)
                  4'h0: begin
                     sym_i <= 3'h0; //32'h3f3504f3, 1448
                     sym_q <= 3'h0; //32'h3f3504f3, 1448
                  end
                  4'h1: begin
                     sym_i <= 3'h0; //32'h3f3504f3, 1448
                     sym_q <= 3'h7; //32'hbf3504f3, -1448
                  end
                  4'h2: begin
                     sym_i <= 3'h7; //32'hbf3504f3, -1448
                     sym_q <= 3'h0; //32'h3f3504f3, 1448
                  end
                  4'h3: begin
                     sym_i <= 3'h7; //32'hbf3504f3, -1448
                     sym_q <= 3'h7; //32'hbf3504f3, -1448
                  end
                  4'h4: begin
                     sym_i <= 3'h1; //32'h3f7746ea, 1978
                     sym_q <= 3'h2; //32'h3e8483ee, 530
                  end
                  4'h5: begin
                     sym_i <= 3'h1; //32'h3f7746ea, 1978
                     sym_q <= 3'h5; //32'hbe8483ee, -530
                  end
                  4'h6: begin
                     sym_i <= 3'h6; //32'hbf7746ea, -1978
                     sym_q <= 3'h2; //32'h3e8483ee, 530
                  end
                  4'h7: begin
                     sym_i <= 3'h6; //32'hbf7746ea, -1978
                     sym_q <= 3'h5; //32'hbe8483ee, -530
                  end
                  4'h8: begin
                     sym_i <= 3'h2; //32'h3e8483ee, 530
                     sym_q <= 3'h1; //32'h3f7746ea, 1978
                  end
                  4'h9: begin
                     sym_i <= 3'h2; //32'h3e8483ee, 530
                     sym_q <= 3'h6; //32'hbf7746ea, -1978
                  end
                  4'hA: begin
                     sym_i <= 3'h5; //32'hbe8483ee, -530
                     sym_q <= 3'h1; //32'h3f7746ea, 1978
                  end
                  4'hB: begin
                     sym_i <= 3'h5; //32'hbe8483ee, -530
                     sym_q <= 3'h6; //32'hbf7746ea, -1978
                  end
                  4'hC: begin
                     sym_i <= 3'h3; //32'h3e8cdeff, 563
                     sym_q <= 3'h3; //32'h3e8cdeff, 563
                  end
                  4'hD: begin
                     sym_i <= 3'h3; //32'h3e8cdeff, 563
                     sym_q <= 3'h4; //32'hbe8cdeff, -563
                  end
                  4'hE: begin
                     sym_i <= 3'h4; //32'hbe8cdeff, -563
                     sym_q <= 3'h3; //32'h3e8cdeff, 563
                  end
                  4'hF: begin
                     sym_i <= 3'h4; //32'hbe8cdeff, -563
                     sym_q <= 3'h4; //32'hbe8cdeff, -563
                  end
               endcase // collected_input case
            end // if collected_valid_reg2
            else begin
               sym_i         <= 3'h0;
               sym_q         <= 3'h0;
               valid_out     <= 1'b0;
            end
         end // if enabled
      end // else not reset
   end // main always

endmodule // dvbs2_bitmapper
