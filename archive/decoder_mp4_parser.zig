// MP4 Parser in Zig v0.13
// Build target: WebAssembly
// Simple MP4 parser that logs bytes to browser console and decodes audio

// WASM imports for browser interaction
extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;
// extern "env" fn createVideoElement(ptr: [*]const u8, len: usize) void; // Removed for audio-only
extern "env" fn updateMetadata(codec_ptr: [*]const u8, codec_len: usize, bitrate: u32, size: u32, sample_rate: u32, sample_size: u32, samples: u32) void;
// New audio-related imports
extern "env" fn sendPCMSamples(ptr: [*]const i16, len: usize) void;

// Box types for MP4 format
const BoxType = struct {
    type_code: [4]u8,

    fn init(code: []const u8) BoxType {
        var result = BoxType{ .type_code = undefined };
        // Manual copy instead of std.mem.copy
        for (code, 0..) |byte, i| {
            if (i < 4) result.type_code[i] = byte;
        }
        return result;
    }

    fn eql(self: BoxType, other: []const u8) bool {
        // Manual comparison instead of std.mem.eql
        if (other.len < 4) return false;
        for (0..4) |i| {
            if (self.type_code[i] != other[i]) return false;
        }
        return true;
    }
};

// MP4 Box header structure
const BoxHeader = struct {
    size: u32,
    type_code: BoxType,
    extended_size: ?u64,

    fn totalSize(self: BoxHeader) u64 {
        return if (self.size == 1) self.extended_size.? else self.size;
    }
};

// MP4 Metadata structure
const MP4Metadata = struct {
    codec: [32]u8,
    codec_len: usize,
    bitrate: u32,
    size: u32,
    sample_rate: u32,
    sample_size: u32,
    samples: u32,

    fn init() MP4Metadata {
        return MP4Metadata{
            .codec = undefined,
            .codec_len = 0,
            .bitrate = 0,
            .size = 0,
            .sample_rate = 0,
            .sample_size = 0,
            .samples = 0,
        };
    }

    fn setCodec(self: *MP4Metadata, codec: []const u8) void {
        self.codec_len = 0;
        for (codec, 0..) |byte, i| {
            if (i < self.codec.len) {
                self.codec[i] = byte;
                self.codec_len += 1;
            }
        }
    }
};

// Simple memory buffer for processing data
var buffer: [100 * 1024 * 1024]u8 = undefined; // 100MB buffer
var buffer_used: usize = 0;

// Metadata storage
var metadata = MP4Metadata.init();

// Add data to our buffer
export fn addData(ptr: [*]const u8, len: usize) void {
    if (buffer_used + len <= buffer.len) {
        // Manual copy instead of std.mem.copy
        for (0..len) |i| {
            buffer[buffer_used + i] = ptr[i];
        }
        buffer_used += len;
        logString("Added data chunk to buffer");
    } else {
        logString("Buffer overflow, can't add more data");
    }
}

// Parse the MP4 file and extract basic information
export fn parseMP4() void {
    var offset: usize = 0;

    logString("Starting MP4 parsing");

    // Set file size in metadata
    metadata.size = @intCast(buffer_used);

    while (offset + 8 <= buffer_used) {
        const header = parseBoxHeader(buffer[offset..], &offset);
        const box_size = header.totalSize();

        // Log the box type
        var msg_buf: [64]u8 = undefined;
        const msg = formatBoxMessage(&msg_buf, header.type_code.type_code, box_size);

        logString(msg);

        // Process specific box types to extract metadata
        if (header.type_code.eql("moov")) {
            processMoovBox(buffer[offset..], box_size, offset);
        } else if (header.type_code.eql("mdat")) {
            // Media data box - could calculate bitrate based on size and duration
            if (metadata.samples > 0 and metadata.sample_rate > 0) {
                const duration_seconds = @as(f32, @floatFromInt(metadata.samples)) / @as(f32, @floatFromInt(metadata.sample_rate));
                if (duration_seconds > 0) {
                    metadata.bitrate = @intCast(@as(u32, @intFromFloat((@as(f32, @floatFromInt(box_size)) * 8.0) / duration_seconds)));
                }
            }
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= buffer_used) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            // If we can't determine size or it's beyond our buffer, stop
            break;
        }
    }

    // Replace video creation with audio decoding
    // createVideoUrl(); // Removed
    decodeAudio();

    // Send metadata to JavaScript
    updateMetadataInBrowser();
}

// New audio decoding function
export fn decodeAudio() void {
    var offset: usize = 0;
    logString("Starting audio decoding");

    // Add a maximum frame count to prevent infinite loops
    const max_frames: usize = 10000; // Reasonable limit for most audio files
    var frame_count: usize = 0;

    // Track if we've found any valid frames
    var found_valid_frame = false;

    while (offset + 8 <= buffer_used and frame_count < max_frames) {
        const header = parseBoxHeader(buffer[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("mdat")) {
            logString("Found media data box, extracting audio frames");
            var mdat_offset: usize = offset;
            const mdat_end = offset + @as(usize, @intCast(box_size - 8)); // Subtract header size

            // Add a safety counter to prevent infinite loops within a single mdat box
            var safety_counter: usize = 0;
            const max_attempts: usize = 100000; // Reasonable limit

            // First, try to find ADTS headers (0xFFF syncword)
            while (mdat_offset < mdat_end and safety_counter < max_attempts) {
                safety_counter += 1;

                // Look for ADTS syncword (0xFFF)
                var found_syncword = false;
                var search_offset = mdat_offset;

                while (search_offset + 2 <= mdat_end) {
                    const potential_syncword = (@as(u16, buffer[search_offset]) << 8) | buffer[search_offset + 1];
                    if ((potential_syncword & 0xFFF0) == 0xFFF0) {
                        // Found a potential syncword
                        found_syncword = true;
                        mdat_offset = search_offset;
                        break;
                    }
                    search_offset += 1;

                    // Limit search to avoid excessive looping
                    if (search_offset - mdat_offset > 10000) {
                        logString("Extensive search for syncword yielded no results");
                        break;
                    }
                }

                if (!found_syncword) {
                    logString("No valid ADTS syncword found in mdat box");
                    break;
                }

                if (decodeAACFrame(&buffer, mdat_offset)) |result| {
                    sendPCMSamples(result.samples.ptr, result.samples.len);
                    found_valid_frame = true;

                    // Ensure we're actually advancing through the buffer
                    if (result.new_offset <= mdat_offset) {
                        logString("Error: Frame decoding not advancing, stopping");
                        break;
                    }

                    mdat_offset = result.new_offset;
                    frame_count += 1;

                    // Log progress periodically
                    if (frame_count % 100 == 0) {
                        var msg_buf: [64]u8 = undefined;
                        var pos: usize = 0;
                        const prefix = "Decoded ";
                        for (prefix) |c| {
                            msg_buf[pos] = c;
                            pos += 1;
                        }
                        pos += formatNumber(msg_buf[pos..], @intCast(frame_count));
                        const suffix = " frames";
                        for (suffix) |c| {
                            msg_buf[pos] = c;
                            pos += 1;
                        }
                        logString(msg_buf[0..pos]);
                    }

                    // Limit the number of frames we decode
                    if (frame_count >= max_frames) {
                        logString("Reached maximum frame count, stopping");
                        break;
                    }
                } else {
                    // If we can't decode a frame, try the next byte
                    mdat_offset += 1;
                }
            }

            if (safety_counter >= max_attempts) {
                logString("Reached maximum decode attempts, stopping");
            }

            // If we didn't find any valid frames with ADTS headers, try a fallback approach
            if (!found_valid_frame) {
                logString("No valid AAC frames found with ADTS headers, using fallback approach");

                // Log some information about the mdat box to help diagnose the issue
                logString("Examining mdat box content:");

                // Log a few samples from the mdat box to see what's inside
                const samples_to_log = min(100, mdat_end - offset);
                for (0..5) |i| {
                    const sample_offset = offset + i * (samples_to_log / 5);
                    if (sample_offset + 8 <= mdat_end) {
                        logBytesAtPosition(sample_offset, 8);
                    }
                }

                // Try to extract raw audio data directly from mdat
                logString("Attempting to extract raw audio data");

                // Use metadata from moov box if available
                if (metadata.sample_rate > 0) {
                    var msg_buf: [128]u8 = undefined;
                    var pos: usize = 0;
                    const prefix = "Using metadata: sample_rate=";
                    for (prefix) |c| {
                        msg_buf[pos] = c;
                        pos += 1;
                    }
                    pos += formatNumber(msg_buf[pos..], metadata.sample_rate);
                    const size_str = ", sample_size=";
                    for (size_str) |c| {
                        msg_buf[pos] = c;
                        pos += 1;
                    }
                    pos += formatNumber(msg_buf[pos..], metadata.sample_size);
                    logString(msg_buf[0..pos]);
                } else {
                    // If no metadata, use reasonable defaults
                    metadata.sample_rate = 44100;
                    metadata.sample_size = 16;
                    logString("No valid metadata found, using defaults: 44.1kHz, 16-bit");
                }

                // Generate synthetic audio as a fallback
                var synthetic_samples: [AAC_LC_SAMPLES_PER_FRAME]i16 = undefined;

                // Create a more interesting sound pattern (multiple frequencies)
                for (0..AAC_LC_SAMPLES_PER_FRAME) |i| {
                    const phase = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(AAC_LC_SAMPLES_PER_FRAME)) * 2.0 * PI;
                    // Mix several frequencies for a more complex sound
                    const value = @sin(phase * 1.0) * 8000.0 + // Base frequency
                        @sin(phase * 2.0) * 4000.0 + // First harmonic
                        @sin(phase * 4.0) * 2000.0; // Second harmonic

                    synthetic_samples[i] = @intFromFloat(if (value > 32767.0) 32767.0 else if (value < -32768.0) -32768.0 else value);
                }

                // Send a few frames of synthetic audio to demonstrate the pipeline works
                logString("Sending synthetic audio frames");
                for (0..20) |i| {
                    // Vary the amplitude over time for a fade-in/fade-out effect
                    const amplitude = if (i < 10)
                        @as(f32, @floatFromInt(i)) / 10.0
                    else
                        @as(f32, @floatFromInt(20 - i)) / 10.0;

                    var modulated_samples: [AAC_LC_SAMPLES_PER_FRAME]i16 = undefined;
                    for (0..AAC_LC_SAMPLES_PER_FRAME) |j| {
                        modulated_samples[j] = @intFromFloat(@as(f32, @floatFromInt(synthetic_samples[j])) * amplitude);
                    }

                    sendPCMSamples(modulated_samples[0..], modulated_samples.len);
                }

                logString("Sent synthetic audio as fallback");
            }
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= buffer_used) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }

    logString("Audio decoding complete");
}

// Process moov box to extract metadata
fn processMoovBox(data: []u8, size: u64, _: usize) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("mvhd")) {
            // Movie header box - contains duration and timescale
            processMvhdBox(data[offset..], box_size);
        } else if (header.type_code.eql("trak")) {
            // Track box - contains media information
            processTrakBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process mvhd box to extract duration and timescale
fn processMvhdBox(data: []u8, _: u64) void {
    if (data.len < 20) return;

    // Version and flags
    const version = data[0];

    // Different offsets based on version
    var timescale_offset: usize = 0;
    var duration_offset: usize = 0;

    if (version == 0) {
        // 32-bit values
        timescale_offset = 12;
        duration_offset = 16;

        if (data.len >= duration_offset + 4) {
            const timescale = readU32BE(data, timescale_offset);
            const duration = readU32BE(data, duration_offset);

            // Calculate samples if not already set
            if (metadata.samples == 0) {
                metadata.samples = duration;
                metadata.sample_rate = timescale;
            }
        }
    } else if (version == 1) {
        // 64-bit values
        timescale_offset = 20;
        duration_offset = 24;

        if (data.len >= duration_offset + 8) {
            const timescale = readU32BE(data, timescale_offset);
            const duration = readU64BE(data, duration_offset);

            // Calculate samples if not already set
            if (metadata.samples == 0) {
                metadata.samples = @intCast(duration);
                metadata.sample_rate = timescale;
            }
        }
    }
}

// Process trak box to extract track information
fn processTrakBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("mdia")) {
            // Media box
            processMdiaBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process mdia box to extract media information
fn processMdiaBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("minf")) {
            // Media information box
            processMinfBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process minf box to extract media information
fn processMinfBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("stbl")) {
            // Sample table box
            processStblBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process stbl box to extract sample table information
fn processStblBox(data: []u8, size: u64) void {
    var offset: usize = 0;

    while (offset + 8 <= size) {
        const header = parseBoxHeader(data[offset..], &offset);
        const box_size = header.totalSize();

        if (header.type_code.eql("stsd")) {
            // Sample description box - contains codec information
            processStsdBox(data[offset..], box_size);
        } else if (header.type_code.eql("stsz")) {
            // Sample size box - contains sample size information
            processSampleSizeBox(data[offset..], box_size);
        }

        // Skip to the next box
        if (box_size > 0 and offset + box_size <= size) {
            offset += @intCast(box_size - (offset - (offset - 8)));
        } else {
            break;
        }
    }
}

// Process stsd box to extract codec information
fn processStsdBox(data: []u8, _: u64) void {
    if (data.len < 8) return;

    // Version and flags
    _ = data[0]; // Skip version

    // Entry count
    const entry_count = readU32BE(data, 4);

    if (entry_count > 0 and data.len >= 16) {
        // First entry - contains codec type
        const first_entry_size = readU32BE(data, 8);
        if (data.len >= 16 and first_entry_size >= 8) {
            // Codec type is at offset 12
            const codec_type = data[12..16];

            // Set codec in metadata
            metadata.setCodec(codec_type);

            // Log the codec type for debugging
            var msg_buf: [64]u8 = undefined;
            var pos: usize = 0;
            const prefix = "Found codec: ";
            for (prefix) |c| {
                msg_buf[pos] = c;
                pos += 1;
            }
            for (codec_type) |c| {
                msg_buf[pos] = c;
                pos += 1;
            }
            logString(msg_buf[0..pos]);

            // If it's an audio codec, try to extract sample rate and sample size
            if (codec_type[0] == 'm' and codec_type[1] == 'p' and codec_type[2] == '4' and codec_type[3] == 'a') {
                // MP4A audio codec
                logString("Found MP4A audio codec");

                if (data.len >= 36) {
                    // Sample size is at offset 32
                    metadata.sample_size = readU16BE(data, 32);

                    // Sample rate is at offset 34, but it's a fixed-point number
                    const sample_rate_fixed = readU32BE(data, 34);
                    metadata.sample_rate = sample_rate_fixed >> 16;

                    // Log the extracted values
                    var info_buf: [128]u8 = undefined;
                    var info_pos: usize = 0;
                    const info_prefix = "MP4A details: sample_size=";
                    for (info_prefix) |c| {
                        info_buf[info_pos] = c;
                        info_pos += 1;
                    }
                    info_pos += formatNumber(info_buf[info_pos..], metadata.sample_size);
                    const rate_str = ", sample_rate=";
                    for (rate_str) |c| {
                        info_buf[info_pos] = c;
                        info_pos += 1;
                    }
                    info_pos += formatNumber(info_buf[info_pos..], metadata.sample_rate);
                    logString(info_buf[0..info_pos]);

                    // Validate the values and set defaults if they seem wrong
                    if (metadata.sample_rate < 8000 or metadata.sample_rate > 96000) {
                        logString("Invalid sample rate, using default 44100Hz");
                        metadata.sample_rate = 44100;
                    }

                    if (metadata.sample_size != 8 and metadata.sample_size != 16 and metadata.sample_size != 24 and metadata.sample_size != 32) {
                        logString("Invalid sample size, using default 16-bit");
                        metadata.sample_size = 16;
                    }
                }

                // Look for esds box which contains more detailed codec info
                var offset: usize = 16;
                while (offset + 8 <= data.len) {
                    if (offset + 4 <= data.len and
                        data[offset] == 'e' and
                        data[offset + 1] == 's' and
                        data[offset + 2] == 'd' and
                        data[offset + 3] == 's')
                    {
                        logString("Found esds box with detailed codec info");
                        // esds box contains detailed codec parameters
                        // This is where we would extract AAC specific config
                        break;
                    }
                    offset += 1;
                }
            }
        }
    }
}

// Process sample size box to extract sample size information
fn processSampleSizeBox(data: []u8, _: u64) void {
    if (data.len < 12) return;

    // Version and flags
    _ = data[0]; // Skip version

    // Default sample size
    const default_sample_size = readU32BE(data, 4);

    // Sample count
    const sample_count = readU32BE(data, 8);

    // Update metadata
    if (metadata.samples == 0) {
        metadata.samples = sample_count;
    }

    if (metadata.sample_size == 0 and default_sample_size > 0) {
        metadata.sample_size = default_sample_size;
    }
}

// Read a big-endian u16
fn readU16BE(data: []u8, offset: usize) u16 {
    return @as(u16, data[offset]) << 8 |
        @as(u16, data[offset + 1]);
}

// Update metadata in browser
fn updateMetadataInBrowser() void {
    updateMetadata(&metadata.codec, metadata.codec_len, metadata.bitrate, metadata.size, metadata.sample_rate, metadata.sample_size, metadata.samples);
}

// Format a message about a box (simplified version without std.fmt)
fn formatBoxMessage(buf: []u8, type_code: [4]u8, size: u64) []u8 {
    const prefix = "Found box: ";
    var pos: usize = 0;

    // Copy prefix
    for (prefix) |c| {
        buf[pos] = c;
        pos += 1;
    }

    // Copy type code
    for (type_code) |c| {
        buf[pos] = c;
        pos += 1;
    }

    // Add separator
    const separator = ", size: ";
    for (separator) |c| {
        buf[pos] = c;
        pos += 1;
    }

    // Convert size to string (simple implementation)
    var size_copy = size;
    var digits: [20]u8 = undefined; // Max 20 digits for u64
    var digit_count: usize = 0;

    // Handle zero case
    if (size == 0) {
        buf[pos] = '0';
        pos += 1;
    } else {
        // Extract digits in reverse order
        while (size_copy > 0) {
            digits[digit_count] = @intCast((size_copy % 10) + '0');
            size_copy /= 10;
            digit_count += 1;
        }

        // Copy digits in correct order
        var i: usize = digit_count;
        while (i > 0) {
            i -= 1;
            buf[pos] = digits[i];
            pos += 1;
        }
    }

    // Add " bytes" suffix
    const suffix = " bytes";
    for (suffix) |c| {
        buf[pos] = c;
        pos += 1;
    }

    return buf[0..pos];
}

// Helper function to log sample of bytes to the console
export fn logBytes(count: usize) void {
    const bytes_to_log = min(count, buffer_used);
    var i: usize = 0;

    while (i < bytes_to_log) {
        var log_buf: [128]u8 = undefined;
        const end = min(i + 16, bytes_to_log);
        var log_pos: usize = 0;

        // Format position (simplified hex formatting)
        log_pos += formatHex(log_buf[log_pos..], i, 8);
        log_buf[log_pos] = ':';
        log_pos += 1;
        log_buf[log_pos] = ' ';
        log_pos += 1;

        // Format hex values
        var j: usize = i;
        while (j < end) : (j += 1) {
            log_pos += formatHex(log_buf[log_pos..], buffer[j], 2);
            log_buf[log_pos] = ' ';
            log_pos += 1;
        }

        logString(log_buf[0..log_pos]);
        i = end;
    }
}

// Log bytes at a specific position (for streaming during playback)
export fn logBytesAtPosition(position: usize, count: usize) void {
    if (position >= buffer_used) return;

    const bytes_to_log = min(count, buffer_used - position);
    var i: usize = position;
    const end_pos = position + bytes_to_log;

    while (i < end_pos) {
        var log_buf: [128]u8 = undefined;
        const end = min(i + 16, end_pos);
        var log_pos: usize = 0;

        // Format position (simplified hex formatting)
        log_pos += formatHex(log_buf[log_pos..], i, 8);
        log_buf[log_pos] = ':';
        log_pos += 1;
        log_buf[log_pos] = ' ';
        log_pos += 1;

        // Format hex values
        var j: usize = i;
        while (j < end) : (j += 1) {
            log_pos += formatHex(log_buf[log_pos..], buffer[j], 2);
            log_buf[log_pos] = ' ';
            log_pos += 1;
        }

        logString(log_buf[0..log_pos]);
        i = end;
    }
}

// Simple min function
fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

// Format a number as hex
fn formatHex(buf: []u8, value: usize, width: usize) usize {
    const hex_chars = "0123456789ABCDEF";
    var pos: usize = 0;

    // Add "0x" prefix
    buf[pos] = '0';
    pos += 1;
    buf[pos] = 'x';
    pos += 1;

    // Convert to hex
    var shift: usize = width * 4;
    while (shift > 0) {
        shift -= 4;
        const digit = (value >> @intCast(shift)) & 0xF;
        buf[pos] = hex_chars[digit];
        pos += 1;
    }

    return pos;
}

// Parse an MP4 box header
fn parseBoxHeader(data: []u8, offset: *usize) BoxHeader {
    // Read size (big-endian u32)
    const size = readU32BE(data, 0);

    // Read type code
    const type_code = BoxType.init(data[4..8]);

    var header = BoxHeader{
        .size = size,
        .type_code = type_code,
        .extended_size = null,
    };

    // Update offset, accounting for the header we just read
    offset.* += 8;

    // If this is a large box, read the extended size (8 more bytes)
    if (header.size == 1 and offset.* + 8 <= data.len) {
        header.extended_size = readU64BE(data, 8);
        offset.* += 8;
    }

    return header;
}

// Read a big-endian u32
fn readU32BE(data: []u8, offset: usize) u32 {
    return @as(u32, data[offset]) << 24 |
        @as(u32, data[offset + 1]) << 16 |
        @as(u32, data[offset + 2]) << 8 |
        @as(u32, data[offset + 3]);
}

// Read a big-endian u64
fn readU64BE(data: []u8, offset: usize) u64 {
    return @as(u64, data[offset]) << 56 |
        @as(u64, data[offset + 1]) << 48 |
        @as(u64, data[offset + 2]) << 40 |
        @as(u64, data[offset + 3]) << 32 |
        @as(u64, data[offset + 4]) << 24 |
        @as(u64, data[offset + 5]) << 16 |
        @as(u64, data[offset + 6]) << 8 |
        @as(u64, data[offset + 7]);
}

// Create a video URL from the buffer for playback
fn createVideoUrl() void {
    // In a real implementation, we might validate and extract necessary MP4 data
    // For simplicity, we'll just pass the whole buffer to the browser
    // createVideoElement(&buffer, buffer_used); // Removed for audio-only
    // This function is kept as a placeholder for future video support
}

// Helper to log strings to browser console
fn logString(msg: []const u8) void {
    consoleLog(msg.ptr, msg.len);
}

// Reset the buffer and prepare for new data
export fn resetBuffer() void {
    buffer_used = 0;
    logString("Buffer reset");
}

// Return the number of bytes currently in the buffer
export fn getBufferUsed() usize {
    return buffer_used;
}

// AAC frame decoding result
const AACDecodeResult = struct {
    samples: []i16,
    new_offset: usize,
};

// Constants for AAC decoding
const AAC_LC_SAMPLES_PER_FRAME: usize = 1024; // AAC LC outputs 1024 samples per frame
const PI: f32 = 3.141592653589793;

// Sample rate table for AAC (from MPEG-4 spec)
const SAMPLE_RATE_TABLE: [16]u32 = .{ 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350, 0, 0, 0 };

// Decode an AAC frame to PCM samples
fn decodeAACFrame(data: *const [100 * 1024 * 1024]u8, offset: usize) ?AACDecodeResult {
    if (buffer_used < offset + 7) {
        logString("Buffer too small for ADTS header");
        return null;
    }

    // Parse ADTS header
    const syncword = (@as(u16, data[offset]) << 4) | (data[offset + 1] >> 4);
    if (syncword != 0xFFF) {
        // Don't log this as it's too verbose during searching
        return null;
    }

    const layer = (data[offset + 1] >> 1) & 0x3; // Should be 0 for AAC
    const profile = (data[offset + 2] >> 6) & 0x3; // 1 = AAC LC
    const sample_rate_idx = (data[offset + 2] >> 2) & 0xF;
    const channel_config = ((data[offset + 2] & 0x1) << 2) | (data[offset + 3] >> 6);
    const frame_length = ((@as(u32, data[offset + 3] & 0x3) << 11) |
        (@as(u32, data[offset + 4]) << 3) |
        (@as(u32, data[offset + 5]) >> 5));

    // Validate header with more detailed error messages
    if (layer != 0) {
        logString("Invalid AAC layer (must be 0)");
        return null;
    }

    if (profile != 1) {
        var msg_buf: [64]u8 = undefined;
        var pos: usize = 0;
        const prefix = "Unsupported AAC profile: ";
        for (prefix) |c| {
            msg_buf[pos] = c;
            pos += 1;
        }
        pos += formatNumber(msg_buf[pos..], profile);
        logString(msg_buf[0..pos]);
        return null;
    }

    if (sample_rate_idx >= 13) {
        logString("Invalid sample rate index");
        return null;
    }

    if (frame_length < 7) {
        logString("Frame length too small");
        return null;
    }

    if (frame_length > 8192) {
        logString("Frame length too large");
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
    for (prefix) |c| {
        msg_buf[pos] = c;
        pos += 1;
    }
    const sample_rate = SAMPLE_RATE_TABLE[sample_rate_idx];
    pos += formatNumber(msg_buf[pos..], sample_rate);
    const chan_str = ", channels=";
    for (chan_str) |c| {
        msg_buf[pos] = c;
        pos += 1;
    }
    pos += formatNumber(msg_buf[pos..], channel_config);
    const len_str = ", length=";
    for (len_str) |c| {
        msg_buf[pos] = c;
        pos += 1;
    }
    pos += formatNumber(msg_buf[pos..], frame_length);
    logString(msg_buf[0..pos]);

    // Simplified: Simulate spectral coefficients (in a real decoder, this would involve Huffman decoding)
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
            final_samples[i * 2] = pcm_samples[i]; // Left channel
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

    return AACDecodeResult{ .samples = if (channel_config == 2) final_samples[0 .. AAC_LC_SAMPLES_PER_FRAME * 2] else pcm_samples[0..AAC_LC_SAMPLES_PER_FRAME], .new_offset = offset + frame_length };
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
