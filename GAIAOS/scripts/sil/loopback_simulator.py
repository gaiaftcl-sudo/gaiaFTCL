import zmq
import struct
import argparse
import time
import numpy as np
from zmq_wire_format import pack_header, pack_payload, FORMAT_COMPLEX_FLOAT32

class LoopbackSimulator:
    def __init__(self, pub_port: int, sub_port: int, sample_rate: int):
        self.context = zmq.Context()
        self.pub_socket = self.context.socket(zmq.PUB)
        self.pub_socket.bind(f"tcp://*:{pub_port}")
        
        self.sub_socket = self.context.socket(zmq.SUB)
        self.sub_socket.bind(f"tcp://*:{sub_port}")
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "")
        
        self.sample_rate = sample_rate
        self.chunk_size = sample_rate // 10
        self.t_start = time.time()
        self.total_samples = 0
        
        # Realistic phase-acquisition latency (≥ 20s for 0.05 Hz)
        self.phase_acquisition_latency = 20.0
        self.phase_acquired = False
        
        # State
        self.tx_active = False
        self.tx_params = None
        self.tx_start_time = 0
        
    def generate_signal(self, t: np.ndarray, nonce: bytes) -> np.ndarray:
        nonce_val = int.from_bytes(nonce, byteorder='little')
        prbs = (nonce_val & 0xFF) / 255.0
        
        # Edge case: clock drift (simulate phase slip)
        clock_drift = 0.0001 * t
        
        fundamental = np.sin(2 * np.pi * 0.05 * (t + clock_drift))
        am_envelope = 1.0 + 0.1 * prbs
        noise_60hz = 0.3 * np.sin(2 * np.pi * 60.0 * t)
        
        # Edge case: Nyquist aliasing (inject high freq noise)
        nyquist_noise = 0.1 * np.sin(2 * np.pi * (self.sample_rate / 2.0 + 10) * t)
        
        awgn = np.random.normal(0, 0.05, size=t.shape)
        
        signal = am_envelope * fundamental + noise_60hz + nyquist_noise + awgn
        
        # Loopback: destructive interference
        if self.tx_active and self.tx_params:
            freq, phase, duty_cycle, amplitude = self.tx_params
            # Apply interference if phase is correct (180 deg)
            if abs(phase - 180.0) <= 5.0 and abs(freq - 0.05) <= 0.1:
                interference = amplitude * np.sin(2 * np.pi * freq * t + np.radians(phase))
                signal += interference
                
        return signal + 1j * np.zeros_like(signal)

    def run(self):
        print("Loopback Simulator running...")
        nonce = os.urandom(16)
        
        while True:
            t = np.arange(self.total_samples, self.total_samples + self.chunk_size) / self.sample_rate
            signal = self.generate_signal(t, nonce)
            
            header = pack_header(self.sample_rate, FORMAT_COMPLEX_FLOAT32, 1)
            payload = pack_payload(signal, FORMAT_COMPLEX_FLOAT32)
            
            self.pub_socket.send_multipart([header, payload])
            self.total_samples += self.chunk_size
            
            # Check TX delivery
            try:
                tx_msg = self.sub_socket.recv_multipart(flags=zmq.NOBLOCK)
                if len(tx_msg) == 2:
                    _, payload = tx_msg
                    if len(payload) == 24:
                        freq, phase, duty_cycle, amplitude, timestamp = struct.unpack('<ffffd', payload)
                        
                        elapsed = time.time() - self.t_start
                        if elapsed < self.phase_acquisition_latency:
                            print(f"TX ignored: Phase acquisition not complete ({elapsed:.1f}s < {self.phase_acquisition_latency}s)")
                        else:
                            # Edge case: collision (TX issued while RX is mid-pulse)
                            if self.tx_active:
                                print("TX Collision detected!")
                            else:
                                self.tx_active = True
                                self.tx_params = (freq, phase, duty_cycle, amplitude)
                                self.tx_start_time = time.time()
                                print(f"TX Active: freq={freq}, phase={phase}")
            except zmq.Again:
                pass
                
            elapsed = time.time() - self.t_start
            expected = self.total_samples / self.sample_rate
            if expected > elapsed:
                time.sleep(expected - elapsed)

if __name__ == "__main__":
    import os
    parser = argparse.ArgumentParser(description="Loopback Simulator")
    parser.add_argument('--pub-port', type=int, default=5555)
    parser.add_argument('--sub-port', type=int, default=5556)
    parser.add_argument('--sample-rate', type=int, default=1000)
    args = parser.parse_args()
    
    sim = LoopbackSimulator(args.pub_port, args.sub_port, args.sample_rate)
    sim.run()
