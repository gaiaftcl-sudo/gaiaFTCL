import zmq
import time
import numpy as np
import struct
import argparse
import os
from zmq_wire_format import pack_header, pack_payload, FORMAT_COMPLEX_FLOAT32

def generate_synthetic_signal(t: np.ndarray, nonce: bytes) -> np.ndarray:
    # 128-bit nonce PRBS for amplitude modulation
    # Just a simple deterministic modulation based on nonce for anti-spoofing
    nonce_val = int.from_bytes(nonce, byteorder='little')
    prbs = (nonce_val & 0xFF) / 255.0
    
    # 0.05 Hz fundamental
    fundamental = np.sin(2 * np.pi * 0.05 * t)
    
    # Amplitude modulation
    am_envelope = 1.0 + 0.1 * prbs
    
    # 60 Hz noise
    noise_60hz = 0.3 * np.sin(2 * np.pi * 60.0 * t)
    
    # AWGN
    awgn = np.random.normal(0, 0.05, size=t.shape)
    
    signal = am_envelope * fundamental + noise_60hz + awgn
    
    # Convert to complex
    return signal + 1j * np.zeros_like(signal)

def main():
    parser = argparse.ArgumentParser(description="Mock S4 Epistemic Edge (GNU Radio + ZeroMQ)")
    parser.add_argument('--pub-port', type=int, default=5555, help='ZMQ PUB port for RX ingestion')
    parser.add_argument('--sub-port', type=int, default=5556, help='ZMQ SUB port for TX delivery')
    parser.add_argument('--sample-rate', type=int, default=1000, help='Sample rate in Hz')
    args = parser.parse_args()

    context = zmq.Context()
    
    # PUB socket for RX (Ingestion)
    pub_socket = context.socket(zmq.PUB)
    pub_socket.bind(f"tcp://*:{args.pub_port}")
    
    # SUB socket for TX (Delivery)
    sub_socket = context.socket(zmq.SUB)
    sub_socket.bind(f"tcp://*:{args.sub_port}")
    sub_socket.setsockopt_string(zmq.SUBSCRIBE, "")
    
    print(f"Mock S4 Edge running on PUB port {args.pub_port} and SUB port {args.sub_port}")
    
    sample_rate = args.sample_rate
    chunk_size = sample_rate // 10 # 100ms chunks
    
    t_start = time.time()
    total_samples = 0
    
    # Generate 128-bit nonce
    nonce = os.urandom(16)
    print(f"Generated 128-bit nonce: {nonce.hex()}")
    
    while True:
        # Generate signal chunk
        t = np.arange(total_samples, total_samples + chunk_size) / sample_rate
        signal = generate_synthetic_signal(t, nonce)
        
        # Pack header and payload
        header = pack_header(sample_rate, FORMAT_COMPLEX_FLOAT32, 1)
        payload = pack_payload(signal, FORMAT_COMPLEX_FLOAT32)
        
        # Send multipart message
        pub_socket.send_multipart([header, payload])
        
        total_samples += chunk_size
        
        # Check for TX delivery (non-blocking)
        try:
            tx_msg = sub_socket.recv_multipart(flags=zmq.NOBLOCK)
            print(f"Received TX delivery: {len(tx_msg)} frames")
            # Loopback simulator will handle this
        except zmq.Again:
            pass
            
        # Sleep to maintain real-time rate
        elapsed = time.time() - t_start
        expected = total_samples / sample_rate
        if expected > elapsed:
            time.sleep(expected - elapsed)

if __name__ == "__main__":
    main()
