import argparse
import numpy as np
import time
from typing import Optional

from realtime_convolution import RealTimeConvolver  # type: ignore


def run_benchmark(
    block_size: int = 1024,
    ir_length: int = 256,
    angles: int = 4,
    blocks: int = 1000,
    samplerate: int = 48000,
    seed: Optional[int] = None,
) -> None:
    """Run the benchmark with synthetic BRIR data."""

    if seed is not None:
        np.random.seed(seed)
    angle_vals = np.linspace(0, 360, angles, endpoint=False)
    brirs = {
        float(a): (np.random.randn(ir_length), np.random.randn(ir_length))
        for a in angle_vals
    }
    engine = RealTimeConvolver(brirs, samplerate=samplerate, block_size=block_size)  # type: ignore[arg-type]
    print(
        f"Running benchmark with block_size={block_size}, ir_length={ir_length}, "
        f"angles={angles}, blocks={blocks}, samplerate={samplerate}" +
        (f", seed={seed}" if seed is not None else "")
    )
    input_block = np.random.randn(2, block_size)
    start = time.perf_counter()
    for _ in range(blocks):
        engine.process_block(input_block)
    elapsed = time.perf_counter() - start
    print(
        f"Processed {blocks} blocks in {elapsed:.3f}s "
        f"({blocks/elapsed:.1f} blocks/s)"
    )
    print(f"Average latency per block: {elapsed/blocks*1000:.3f} ms")


def main():
    parser = argparse.ArgumentParser(
        description="Benchmark RealTimeConvolver with synthetic data"
    )
    parser.add_argument("--blocks", type=int, default=1000, help="Number of blocks")
    parser.add_argument("--block_size", type=int, default=1024, help="Block size")
    parser.add_argument(
        "--ir_length", type=int, default=256, help="Length of synthetic impulse responses"
    )
    parser.add_argument(
        "--angles", type=int, default=4, help="Number of synthetic BRIR angles"
    )
    parser.add_argument(
        "--samplerate", type=int, default=48000, help="Sample rate for synthetic data"
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Random seed for reproducible results",
    )
    args = parser.parse_args()
    run_benchmark(
        block_size=args.block_size,
        ir_length=args.ir_length,
        angles=args.angles,
        blocks=args.blocks,
        samplerate=args.samplerate,
        seed=args.seed,
    )


if __name__ == "__main__":
    main()