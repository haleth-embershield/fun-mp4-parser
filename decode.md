### Key Concepts for AAC Decoding
1. **ADTS Header**: The Audio Data Transport Stream (ADTS) header encapsulates each AAC frame in the `mdat` box, providing metadata like frame length, sample rate, and channel configuration.
2. **Spectral Data**: AAC encodes audio in the frequency domain using MDCT coefficients, compressed with Huffman coding.
3. **IMDCT**: The Inverse MDCT converts these coefficients back to time-domain PCM samples (typically 1024 samples per frame for AAC LC).
4. **Output**: PCM samples are 16-bit signed integers suitable for playback.

For simplicity, this implementation will:
- Parse the ADTS header fully to validate the frame and extract key parameters.
- Simulate spectral data extraction (since full Huffman decoding requires extensive tables from the AAC spec).
- Apply a basic IMDCT to generate PCM samples.

---

### Updated Zig Code for `decodeAACFrame`

Replace the placeholder section in your existing `decodeAACFrame` with the following code. This implementation assumes stereo AAC LC audio (2 channels, 1024 samples per frame) and includes a simplified IMDCT. Note that real-world AAC decoding would require additional steps (e.g., scale factors, stereo processing, and psychoacoustic adjustments), which are omitted for brevity.

```zig
// AAC frame decoding result
const AACDecodeResult = struct {
    samples: []i16,
    new_offset: usize,
};

// Constants for AAC decoding
const AAC_LC_SAMPLES_PER_FRAME: usize = 1024; // AAC LC outputs 1024 samples per frame
const PI: f32 = 3.141592653589793;

// Sample rate table for AAC (from MPEG-4 spec)
const SAMPLE_RATE_TABLE: [16]u32 = .{ 
    96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 
    16000, 12000, 11025, 8000, 7350, 0, 0, 0 
};

// Decode an AAC frame to PCM samples
fn decodeAACFrame(data: *const [100 * 1024 * 1024]u8, offset: usize) ?AACDecodeResult {
    if (buffer_used < offset + 7) return null;

    // Parse ADTS header
    const syncword = (@as(u16, data[offset]) << 4) | (data[offset + 1] >> 4);
    if (syncword != 0xFFF) {
        logString("Invalid syncword");
        return null;
    }

    const id = (data[offset + 1] >> 3) & 0x1; // 0 = MPEG-4, 1 = MPEG-2
    const layer = (data[offset + 1] >> 1) & 0x3; // Should be 0 for AAC
    const protection_absent = data[offset + 1] & 0x1;
    const profile = (data[offset + 2] >> 6) & 0x3; // 1 = AAC LC
    const sample_rate_idx = (data[offset + 2] >> 2) & 0xF;
    const channel_config = ((data[offset + 2] & 0x1) << 2) | (data[offset + 3] >> 6);
    const frame_length = ((@as(u32, data[offset + 3] & 0x3) << 11) |
                         (@as(u32, data[offset + 4]) << 3) |
                         (@as(u32, data[offset + 5]) >> 5));

    // Validate header
    if (layer != 0 or profile != 1 or sample_rate_idx >= 13 or frame_length < 7 or frame_length > 8192) {
        logString("Invalid AAC header parameters");
        return null;
    }
    if (offset + frame_length > buffer_used) {
        logString("Frame exceeds buffer");
        return null;
    }

    // Log some header info for debugging
    var msg_buf: [128]u8 = undefined;
    var pos: usize = 0;
    const prefix = "AAC Frame: profile=LC, sample_rate=";
    for (prefix) |c| { msg_buf[pos] = c; pos += 1; }
    const sample_rate = SAMPLE_RATE_TABLE[sample_rate_idx];
    pos += formatNumber(&msg_buf[pos..], sample_rate);
    const chan_str = ", channels=";
    for (chan_str) |c| { msg_buf[pos] = c; pos += 1; }
    pos += formatNumber(&msg_buf[pos..], channel_config);
    logString(msg_buf[0..pos]);

    // Skip header (7 bytes if protection_absent, 9 if CRC present)
    const header_size = if (protection_absent == 1) 7 else 9;
    var data_offset = offset + header_size;
    const data_len = frame_length - header_size;

    // Simplified: Simulate spectral coefficients (in a real decoder, this would involve Huffman decoding)
    // For this example, we'll generate synthetic coefficients to demonstrate IMDCT
    var spectral_data: [AAC_LC_SAMPLES_PER_FRAME]f32 = undefined;
    for (0..AAC_LC_SAMPLES_PER_FRAME) |i| {
        // Simulate some frequency content (e.g., a mix of sine waves)
        const freq = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(AAC_LC_SAMPLES_PER_FRAME));
        spectral_data[i] = @sin(freq * 2.0 * PI * 5.0) * 1000.0; // Arbitrary amplitude
    }

    // Perform IMDCT (simplified for one channel)
    var pcm_samples: [AAC_LC_SAMPLES_PER_FRAME]i16 = undefined;
    for (0..AAC_LC_SAMPLES_PER_FRAME) |n| {
        var sum: f32 = 0.0;
        for (0..AAC_LC_SAMPLES_PER_FRAME) |k| {
            const angle = PI / @as(f32, @floatFromInt(AAC_LC_SAMPLES_PER_FRAME)) * 
                         (@as(f32, @floatFromInt(n)) + 0.5 + @as(f32, @floatFromInt(AAC_LC_SAMPLES_PER_FRAME)) / 2.0) * 
                         (@as(f32, @floatFromInt(k)) + 0.5);
            sum += spectral_data[k] * @cos(angle);
        }
        // Scale and clip to 16-bit range
        const scaled = sum * 0.5; // Arbitrary scaling to prevent clipping
        pcm_samples[n] = @intFromFloat(if (scaled > 32767.0) 32767.0 else if (scaled < -32768.0) -32768.0 else scaled);
    }

    // For stereo (channel_config == 2), duplicate samples across channels
    var final_samples: [AAC_LC_SAMPLES_PER_FRAME * 2]i16 = undefined;
    if (channel_config == 2) {
        for (0..AAC_LC_SAMPLES_PER_FRAME) |i| {
            final_samples[i * 2] = pcm_samples[i];     // Left channel
            final_samples[i * 2 + 1] = pcm_samples[i]; // Right channel (duplicate for simplicity)
        }
    } else {
        // Mono (channel_config == 1)
        for (0..AAC_LC_SAMPLES_PER_FRAME) |i| {
            final_samples[i] = pcm_samples[i];
        }
    }

    // Update metadata if not already set
    if (metadata.sample_rate == 0) metadata.sample_rate = sample_rate;
    if (metadata.sample_size == 0) metadata.sample_size = 16; // 16-bit PCM

    return AACDecodeResult{ 
        .samples = if (channel_config == 2) final_samples[0..AAC_LC_SAMPLES_PER_FRAME * 2] else pcm_samples[0..AAC_LC_SAMPLES_PER_FRAME], 
        .new_offset = offset + frame_length 
    };
}

// Helper function to format numbers (since we avoid std.fmt)
fn formatNumber(buf: []u8, value: u32) usize {
    var digits: [10]u8 = undefined;
    var count: usize = 0;
    var val = value;
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    while (val > 0) {
        digits[count] = @intCast((val % 10) + '0');
        val /= 10;
        count += 1;
    }
    var pos: usize = 0;
    while (count > 0) {
        count -= 1;
        buf[pos] = digits[count];
        pos += 1;
    }
    return pos;
}
```

---

### Explanation of Changes

1. **ADTS Header Parsing**:
   - Fully parses the ADTS header to extract `profile` (assuming AAC LC), `sample_rate_idx`, `channel_config`, and `frame_length`.
   - Validates parameters to ensure the frame is decodable.

2. **Spectral Data Simulation**:
   - In a real AAC decoder, you’d parse the bitstream (starting at `data_offset`) using Huffman decoding tables (defined in ISO/IEC 13818-7) to extract MDCT coefficients. For simplicity, this code generates synthetic coefficients (a mix of sine waves) to mimic spectral data.

3. **IMDCT Implementation**:
   - Applies a basic IMDCT to convert the 1024 spectral coefficients into 1024 time-domain samples. The formula follows the MPEG standard:
     \[
     x[n] = \sum_{k=0}^{N-1} X[k] \cos\left(\frac{\pi}{N} \left(n + \frac{1}{2} + \frac{N}{2}\right) \left(k + \frac{1}{2}\right)\right)
     \]
     where \(N = 1024\), \(X[k]\) are the spectral coefficients, and \(x[n]\) are the PCM samples.
   - Scales and clips the output to fit 16-bit signed integers.

4. **Channel Handling**:
   - Supports mono (1 channel) or stereo (2 channels) based on `channel_config`. For stereo, it duplicates the mono samples across both channels (a simplification; real stereo AAC uses joint stereo coding).

5. **Metadata Update**:
   - Sets `sample_rate` and `sample_size` in the metadata if not already set, ensuring compatibility with your JavaScript playback.

---

### Limitations and Next Steps
- **Huffman Decoding Omitted**: Real AAC decoding requires parsing the raw bitstream with Huffman tables (e.g., `scalefac`, `spectral_data`) and applying scale factors. You’d need to implement a bit reader and include the Huffman tables from the AAC spec.
- **Windowing Ignored**: AAC uses overlapping windows (long/short blocks) with a synthesis window function, which this code skips for simplicity.
- **Stereo Simplification**: Real stereo decoding involves Mid/Side or Intensity Stereo, not just duplication.
- **Learning Expansion**: To make this fully functional, study the AAC spec (ISO/IEC 13818-7) or port parts of FAAD2’s `decoder.c` to Zig.

---

### Integration with Your Code
Replace the existing `decodeAACFrame` function in your `mp4_parser.zig` with this version. The rest of your code (e.g., `parseMP4`, `decodeAudio`) will work as-is, calling this function to process each AAC frame and send PCM samples to JavaScript via `sendPCMSamples`.

When you run this with your HTML, you’ll hear a synthetic sine wave (from the simulated spectral data), proving the pipeline works. To decode real AAC audio, you’d need to replace the spectral data simulation with actual bitstream parsing, which is a deeper project.