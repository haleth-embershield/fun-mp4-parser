# WebGPU-based MP4 Decoder Roadmap

This roadmap outlines the implementation steps for creating a WebGPU-powered MP4 decoder that manually processes each layer of the MP4 container format. The goal is to build a learning project to understand modern video and audio codecs, container formats, and hardware-accelerated processing.

## Overview

Our project aims to:
1. Manually decode every aspect of MP4 containers (boxes, atoms, headers)
2. Leverage WebGPU for hardware-accelerated video processing
3. Implement multithreaded processing where appropriate
4. Support cross-browser and cross-device compatibility
5. Maintain and enhance our current data stream capabilities
6. Provide educational insights into codec operation

## Phase 1: MP4 Container Format Understanding (2 weeks)

### MP4 Structure Analysis
- [ ] Complete the MP4 box hierarchy parser
  - Decode all mandatory boxes: ftyp, moov, mdat, mvhd, trak, etc.
  - Properly handle nested container boxes
- [ ] Implement comprehensive metadata extraction
  - Duration, creation date, modification date
  - Video dimensions, frame rate, color space
  - Audio channels, sample rate, bit depth
- [ ] Create visualization of box hierarchy for educational purposes

### Initial Data Handling
- [ ] Optimize buffer management for large files
  - Implement chunked processing to handle files of arbitrary size
  - Create efficient memory pooling for WebAssembly
- [ ] Design data structures for decoded frames
  - Separate structures for video frames, audio samples
  - Metadata association with frames

## Phase 2: Video Decoding Implementation (4 weeks)

### Video Codec Support
- [ ] Implement H.264/AVC parser
  - NAL unit extraction and parsing
  - SPS/PPS parameter extraction
  - Slice type determination
- [ ] Add support for H.265/HEVC (next-gen)
  - Similar structure to H.264 but with enhanced features
- [ ] Setup for hardware acceleration mapping

### WebGPU Integration for Video
- [ ] Setup WebGPU device and adapter handling
  - Feature detection and fallback mechanisms
  - Queue management for command submission
- [ ] Implement compute shader pipelines for:
  - Motion compensation
  - Inverse transform (IDCT/DST)
  - Deblocking filter
  - Sample adaptive offset (for HEVC)
- [ ] Create render pipeline for final YUV to RGB conversion
- [ ] Design buffer strategies for frame data
  - Efficient GPU memory management
  - Double/triple buffering for smooth playback

## Phase 3: Audio Decoding Implementation (3 weeks)

### Audio Codec Support
- [ ] Implement AAC decoder
  - ADTS header parsing
  - Huffman decoding for spectral data
  - IMDCT implementation
  - Channel coupling and reconstruction
- [ ] Add MP3 fallback support
  - Frame header parsing
  - Subband synthesis
- [ ] Design filter architecture for audio effects

### Audio Rendering
- [ ] Integrate with Web Audio API
  - Create AudioContext and buffer management
  - Implement sample rate conversion if needed
- [ ] Build audio processing worklets for effects
  - EQ, compression, spatial effects
- [ ] Synchronize audio with video timeline

## Phase 4: Multithreading & Performance Optimization (3 weeks)

### Thread Architecture
- [ ] Design thread pool system
  - Main thread: UI, coordination, final rendering
  - Worker threads: Decoding, processing
  - Shared memory coordination
- [ ] Implement frame-level parallelism
  - Decode independent frames (I-frames) in parallel
  - Process slices within frames in parallel
- [ ] Create dependency tracking for P and B frames
  - Ensure correct order of operations
  - Reference frame management

### Memory and Synchronization
- [ ] Implement SharedArrayBuffer for frame data
  - Atomic operations for coordination
  - Lock-free algorithms where possible
- [ ] Design queue system for work distribution
  - Priority-based scheduling (I-frames first)
  - Frame reordering for presentation
- [ ] Create profiling and monitoring tools
  - Performance metrics collection
  - Bottleneck identification

## Phase 5: Filter Implementation & Real-time Editing (3 weeks)

### Filter Architecture Design
- [ ] Create modular filter framework
  - Abstract filter interface with standard inputs/outputs
  - Parameter system for configurable settings
  - Chain and graph-based filter processing pipeline
- [ ] Design filter process integration points
  - Pre-decode filters (bitstream manipulation)
  - Post-decode filters (pixel/sample domain)
  - Rendering filters (presentation stage)

### Video Filter Implementation
- [ ] Basic image processing filters
  - Color adjustment (brightness, contrast, saturation, hue)
  - Blur, sharpen, noise reduction
  - Crop, resize, rotation
- [ ] Advanced video filters
  - Temporal filters (motion blur, frame interpolation)
  - Style transfer filters using compute shaders
  - Chroma keying and composition
- [ ] WebGPU-accelerated implementations
  - Fragment shader implementations for pixel-domain filters
  - Compute shader implementations for spatial transformations
  - Optimization for real-time performance

### Audio Filter Implementation
- [ ] Time-domain audio filters
  - Volume adjustment, normalization
  - Noise gate, compression
  - Echo, delay, reverb
- [ ] Frequency-domain filters
  - Parametric EQ, graphic EQ
  - Spectral effects (pitch shift, time stretch)
  - Vocoder, auto-tune
- [ ] Multi-channel audio processing
  - Stereo field manipulation
  - Channel mixing and routing
  - Spatial audio effects

### User Filter Interface
- [ ] Design intuitive filter control UI
  - Visual representation of filter parameters
  - Real-time preview of filter effects
  - Presets and user-defined settings
- [ ] Implement non-destructive editing
  - Filter stack with enable/disable toggles
  - Filter reordering and parameter animation
  - History/undo functionality
- [ ] Export capabilities
  - Save filtered video/audio to new file
  - Export filter settings as shareable presets
  - Screenshot/audio clip generation

## Phase 6: User Interface & Experience (2 weeks)

### Control Interface
- [ ] Build responsive video player UI
  - Play/pause, seek, volume controls
  - Fullscreen and picture-in-picture support
- [ ] Implement timeline with frame-accurate seeking
  - Keyframe indication
  - Thumbnail preview

### Stream Analysis & Visualization
- [ ] Create codec information display
  - Bitrate graphs
  - Frame type distribution
  - GOP structure visualization
- [ ] Implement debug views
  - Motion vector visualization
  - Block type overlay
  - Quantization heatmap

## Phase 7: Browser Compatibility & Deployment (2 weeks)

### Cross-Browser Testing
- [ ] Test and optimize for major browsers
  - Chrome, Firefox, Safari, Edge
  - Mobile browsers (iOS Safari, Chrome for Android)
- [ ] Implement feature detection and fallbacks
  - WebGPU availability
  - SharedArrayBuffer support
  - Worker thread capabilities

### Performance Benchmarking
- [ ] Create test suite with various MP4 files
  - Different resolutions, codecs, bitrates
  - Stress test with complex content
- [ ] Optimize for mobile devices
  - Power efficiency considerations
  - Thermal management strategies

## Technical Approach Details

### WebGPU Implementation Strategy

WebGPU will be used primarily for:
1. **Video Decoding**: While full codec implementation in shaders is complex, we'll use compute shaders for:
   - Motion compensation (adding motion vectors to reference frames)
   - Inverse transforms (converting frequency coefficients to pixel values)
   - Post-processing (deblocking, deringing)
   - Color conversion (YUV to RGB)

2. **Parallel Processing**: Using compute shaders to process multiple macroblocks simultaneously
   - Grid-based dispatch aligned with video structure
   - Workgroups mapping to CTUs/macroblocks

3. **Rendering**: Final composition and display
   - Texture mapping for frame display
   - Shader-based video filters (brightness, contrast, etc.)

### Filter Implementation Strategy

Our approach to implementing filters combines flexibility, performance, and educational value:

1. **Filter Pipeline Architecture**:
   - We'll use a composable pipeline design where filters are modular components
   - Each filter will have a clear input/output specification
   - Filters can be chained, with the output of one becoming the input to the next

2. **Implementation Tiers**:
   - **Tier 1 (Inline)**: Filters applied during the decode/render pipeline
     - These integrate directly into the decode or render steps
     - Examples: YUV adjustments before RGB conversion, simple color transforms
   - **Tier 2 (Post-Processing)**: Filters applied to fully decoded frames
     - These operate on complete frames between decode and display
     - Examples: Blur, sharpen, artistic effects
   - **Tier 3 (Timeline)**: Filters applied across multiple frames
     - These require knowledge of surrounding frames
     - Examples: Temporal noise reduction, motion interpolation

3. **Optimized Processing Locations**:
   - **GPU Compute**: Complex spatial filters, convolutions, matrix operations
   - **Fragment Shaders**: Color adjustments, simple pixel operations, blending
   - **CPU WebAssembly**: Audio filters, control logic, format-specific operations

4. **Real-time Preview Strategy**:
   - Implement progressive quality levels for filters
   - Use lower resolution processing during interaction
   - Apply at full quality for final output or when interaction stops

### Multithreading Architecture

Based on the analysis in multithread.md, we'll implement:

1. **Thread Pool Design**:
   - Main thread: Handles UI, WebGPU operations, and coordination
   - Worker pool: 4-8 workers (configurable based on device)
   - Communication via structured messages and SharedArrayBuffer

2. **Work Distribution**:
   - GOP-level parallelism: Assign Groups of Pictures to different threads
   - Frame-level parallelism: Process independent frames concurrently
   - Slice-level parallelism: Split large frames into processable units

3. **Synchronization Strategy**:
   - Reference frame manager to track dependencies
   - Atomic operations for coordination
   - Presentation buffer to ensure correct playback order
   - Adaptive buffer sizing based on decoding speed

### Data Flow Architecture

1. **Input Pipeline**:
   ```
   User Upload → Chunked Buffer → MP4 Parser → Demuxed Streams
   ```

2. **Processing Pipeline**:
   ```
   Video NALs → Thread Pool → GPU Compute → Filter Chain → Render Pipeline → Canvas
   Audio Frames → Thread Pool → CPU Decode → Audio Filters → Web Audio API → Speakers
   ```

3. **Control Flow**:
   ```
   User Input → Timeline Controller → Decoder Synchronization → Playback
   ```

### Maintaining Background Data Stream

To ensure our current background data stream remains intact:

1. **Abstraction Layer**: Implement a data provider interface that can source from:
   - Current background stream
   - User-uploaded files
   - Network streams

2. **Enhanced Metadata**: Extend current metadata extraction to include:
   - Deeper technical details (profile, level, entropy coding method)
   - Content information (resolution changes, HDR flags)
   - Accessibility features (captions, audio descriptions)

3. **Raw Data Access**: Provide methods to access and inspect:
   - NAL units before decoding
   - Bitstream segments
   - Intermediary decode steps

## Learning Objectives

This implementation will provide insights into:

1. **Container Formats**: MP4/ISO Base Media File Format structure and semantics
2. **Video Codecs**: H.264/AVC and H.265/HEVC operation principles
   - Transform coding (DCT/DST)
   - Motion compensation
   - Entropy coding
   - In-loop filtering
3. **Audio Codecs**: AAC encoding principles
   - Psychoacoustic modeling
   - Modified discrete cosine transform
   - Huffman coding
4. **Graphics Programming**: WebGPU architecture and shader programming
5. **Parallel Processing**: Thread coordination and synchronization patterns

## Implementation Notes

- **Simplified First Pass**: Start with I-frame only decoding for H.264 to establish the pipeline
- **Progressive Enhancement**: Add P-frames, then B-frames, then advanced features
- **Educational Instrumentation**: Add visualization options at each step
- **Performance Monitoring**: Build in metrics gathering from the start

## Timeline

- Phase 1: 2 weeks
- Phase 2: 4 weeks
- Phase 3: 3 weeks
- Phase 4: 3 weeks
- Phase 5: 3 weeks
- Phase 6: 2 weeks
- Phase 7: 2 weeks

Total: 19 weeks (4-5 months) with testing and refinement throughout

## Additional Commentary: Using FFmpeg for Input Preprocessing

### Is Using FFmpeg to Sanitize Input "Cheating"?

Using FFmpeg to convert arbitrary media files to a standardized MP4 format before processing them with our decoder is a pragmatic approach that offers several benefits:

**Advantages:**
1. **Controlled Input**: Ensures we're always working with a known container format and codec combination
2. **Focus on Learning**: Allows us to focus on the specific codecs we want to learn (H.264, AAC) rather than handling every possible format
3. **Progressive Complexity**: We can start with "clean" files and gradually expand to handle more edge cases
4. **Debugging Aid**: When issues arise, we can compare our decoder's output with FFmpeg's to isolate problems

**Educational Perspective:**
This approach isn't "cheating" if:
- We're transparent about what we're doing
- We still implement the full MP4 parsing and codec decoding ourselves
- The preprocessing is used primarily for normalization, not to simplify the actual decoding work

**Implementation Options:**
1. **Server-Side Preprocessing**: Run FFmpeg on a server to convert files before they're processed by our client-side decoder
2. **WebAssembly FFmpeg**: Compile FFmpeg to WebAssembly for in-browser preprocessing (though this adds significant complexity)
3. **Hybrid Approach**: Start with pre-sanitized files, then gradually expand to handle arbitrary inputs directly

**Phase Integration:**
- During Phase 1 (Container Format): Use FFmpeg-normalized files exclusively
- By Phase 3-4: Add direct support for common variations without preprocessing
- Final Phases: Support direct ingestion of arbitrary files where possible

This approach aligns with educational best practices: start with controlled examples to learn the fundamentals, then expand to handle real-world complexity once the basics are understood. 