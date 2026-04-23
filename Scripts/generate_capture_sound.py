#!/usr/bin/env python3

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = PROJECT_ROOT / "Packaging" / "capture.wav"

SAMPLE_RATE = 44100
DURATION = 0.15
NUM_SAMPLES = int(SAMPLE_RATE * DURATION)


def main() -> None:
    PROJECT_ROOT.joinpath("Packaging").mkdir(parents=True, exist_ok=True)
    samples = generate_samples()
    write_wav(samples)
    print(OUTPUT_PATH)


def generate_samples() -> list[int]:
    samples: list[int] = []
    for i in range(NUM_SAMPLES):
        t = i / SAMPLE_RATE
        progress = i / NUM_SAMPLES

        freq = 1200 - 600 * progress
        envelope = (1 - progress) ** 3

        val = math.sin(2 * math.pi * freq * t)
        val += 0.3 * math.sin(2 * math.pi * freq * 2 * t)
        val += 0.15 * math.sin(2 * math.pi * freq * 3 * t)
        val += 0.08 * math.sin(2 * math.pi * 2400 * t) * max(0, 1 - progress * 4)

        val *= envelope * 0.7
        samples.append(int(max(-1, min(1, val)) * 32767))

    return samples


def write_wav(samples: list[int]) -> None:
    with wave.open(str(OUTPUT_PATH), "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(struct.pack(f"<{len(samples)}h", *samples))


if __name__ == "__main__":
    main()
