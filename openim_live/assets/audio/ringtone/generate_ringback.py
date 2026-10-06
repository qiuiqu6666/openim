"""Generate the original waiting tone; run offline with Python's standard library."""

import math
from pathlib import Path
import struct
import wave

SAMPLE_RATE = 16000
TONE_SECONDS = 1
SILENCE_SECONDS = 4
FREQUENCY_HZ = 425
AMPLITUDE = 0.25
FADE_SAMPLES = int(SAMPLE_RATE * 0.01)


def generate(destination):
    tone_samples = SAMPLE_RATE * TONE_SECONDS
    total_samples = SAMPLE_RATE * (TONE_SECONDS + SILENCE_SECONDS)
    frames = bytearray()
    for index in range(total_samples):
        if index < tone_samples:
            envelope = min(1.0, (index + 1) / FADE_SAMPLES,
                           (tone_samples - index) / FADE_SAMPLES)
            value = round(32767 * AMPLITUDE * envelope *
                          math.sin(2 * math.pi * FREQUENCY_HZ *
                                   index / SAMPLE_RATE))
        else:
            value = 0
        frames.extend(struct.pack('<h', value))
    with wave.open(str(destination), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


if __name__ == '__main__':
    generate(Path(__file__).with_name('outgoing_ringback.wav'))
