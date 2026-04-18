import struct
import numpy as np

# Frame 0 (Header, 16 bytes):
# sample_rate_hz (u32 LE)
# sample_format (u8: 0=complex_int16, 1=complex_float32)
# channel_count (u8)
# reserved (10 bytes)

FORMAT_COMPLEX_INT16 = 0
FORMAT_COMPLEX_FLOAT32 = 1

def pack_header(sample_rate_hz: int, sample_format: int, channel_count: int) -> bytes:
    # <I B B 10s
    reserved = b'\x00' * 10
    return struct.pack('<I B B 10s', sample_rate_hz, sample_format, channel_count, reserved)

def unpack_header(header_bytes: bytes):
    if len(header_bytes) != 16:
        raise ValueError(f"Expected 16 bytes for header, got {len(header_bytes)}")
    sample_rate_hz, sample_format, channel_count, reserved = struct.unpack('<I B B 10s', header_bytes)
    return {
        'sample_rate_hz': sample_rate_hz,
        'sample_format': sample_format,
        'channel_count': channel_count,
        'reserved': reserved
    }

def pack_payload(data: np.ndarray, sample_format: int) -> bytes:
    if sample_format == FORMAT_COMPLEX_INT16:
        # Expecting complex data, convert to interleaved int16
        interleaved = np.empty((data.size * 2,), dtype=np.int16)
        interleaved[0::2] = np.real(data).astype(np.int16)
        interleaved[1::2] = np.imag(data).astype(np.int16)
        return interleaved.tobytes()
    elif sample_format == FORMAT_COMPLEX_FLOAT32:
        interleaved = np.empty((data.size * 2,), dtype=np.float32)
        interleaved[0::2] = np.real(data).astype(np.float32)
        interleaved[1::2] = np.imag(data).astype(np.float32)
        return interleaved.tobytes()
    else:
        raise ValueError(f"Unknown sample format: {sample_format}")

def unpack_payload(payload_bytes: bytes, sample_format: int) -> np.ndarray:
    if sample_format == FORMAT_COMPLEX_INT16:
        interleaved = np.frombuffer(payload_bytes, dtype=np.int16)
        return interleaved[0::2] + 1j * interleaved[1::2]
    elif sample_format == FORMAT_COMPLEX_FLOAT32:
        interleaved = np.frombuffer(payload_bytes, dtype=np.float32)
        return interleaved[0::2] + 1j * interleaved[1::2]
    else:
        raise ValueError(f"Unknown sample format: {sample_format}")
