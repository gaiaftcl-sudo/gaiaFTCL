import zmq
import struct
import argparse
import time

def validate_tx_parameters(freq: float, phase: float, duty_cycle: float, amplitude: float, latency: float):
    # Strict acceptance envelope
    # Freq ±0.1Hz, Phase ±5°, Duty cycle ±1%, Amplitude ±2%, Latency ≤ 500ms p99
    
    expected_freq = 0.05
    expected_phase = 180.0
    expected_duty_cycle = 50.0
    expected_amplitude = 1.0
    
    freq_error = abs(freq - expected_freq)
    phase_error = abs(phase - expected_phase)
    duty_cycle_error = abs(duty_cycle - expected_duty_cycle)
    amplitude_error = abs(amplitude - expected_amplitude)
    
    errors = []
    if freq_error > 0.1:
        errors.append(f"Frequency error: {freq_error} > 0.1Hz")
    if phase_error > 5.0:
        errors.append(f"Phase error: {phase_error} > 5°")
    if duty_cycle_error > 1.0:
        errors.append(f"Duty cycle error: {duty_cycle_error} > 1%")
    if amplitude_error > 0.02:
        errors.append(f"Amplitude error: {amplitude_error} > 2%")
    if latency > 0.5:
        errors.append(f"Latency error: {latency} > 500ms")
        
    return errors

def main():
    parser = argparse.ArgumentParser(description="Linux VM OQ Test Runner")
    parser.add_argument('--sub-port', type=int, default=5556, help='ZMQ SUB port for TX delivery')
    args = parser.parse_args()

    context = zmq.Context()
    sub_socket = context.socket(zmq.SUB)
    sub_socket.connect(f"tcp://127.0.0.1:{args.sub_port}")
    sub_socket.setsockopt_string(zmq.SUBSCRIBE, "")
    
    print(f"OQ Test Runner listening on SUB port {args.sub_port}")
    
    while True:
        try:
            msg = sub_socket.recv_multipart()
            if len(msg) == 2:
                header, payload = msg
                # Assuming TX parameters are sent in payload
                # format: freq(f32), phase(f32), duty_cycle(f32), amplitude(f32), timestamp(f64)
                if len(payload) == 24:
                    freq, phase, duty_cycle, amplitude, timestamp = struct.unpack('<ffffd', payload)
                    latency = time.time() - timestamp
                    
                    errors = validate_tx_parameters(freq, phase, duty_cycle, amplitude, latency)
                    if errors:
                        print(f"TX Validation FAILED: {errors}")
                    else:
                        print(f"TX Validation PASSED: freq={freq}, phase={phase}, duty_cycle={duty_cycle}, amplitude={amplitude}, latency={latency}")
                else:
                    print(f"Invalid payload length: {len(payload)}")
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    main()
