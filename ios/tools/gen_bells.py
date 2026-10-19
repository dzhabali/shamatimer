#!/usr/bin/env python3
"""Синтез колоколов ShamaTimer по формуле веб-версии (playSakya/strike/click).

Чистый python (wave/math/random). Пишет WAV 44.1 kHz mono 16-bit во временную
папку и конвертирует afconvert'ом в CAF (LEI16) в ShamaTimer/Resources/Sounds/:
  bell-start.caf  — один playSakya(0.22)
  bell-end.caf    — playSakya(0.24) + через 2.2 с playSakya(0.18)  (< 30 с)
  silence.caf     — 2 с тишины для фонового лупа
Пик нормализуется до -1 dBFS.
Запуск: python3 tools/gen_bells.py
"""
import math, os, random, struct, subprocess, sys, tempfile, wave

SR = 44100
PEAK_DBFS = -1.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'ShamaTimer', 'Resources', 'Sounds')


def strike(buf, t0, freq, gain, dur):
    """Синус с экспоненциальным спуском частоты freq→freq*0.996 за dur,
    атака 8 мс линейно до gain, затем экспоненциальный спад до 0.0008."""
    r = 0.996
    lnr = math.log(r)
    start = int(t0 * SR)
    n = int(dur * SR)
    att = 0.008
    for i in range(n):
        t = i / SR
        # фаза = 2π ∫ f(t) dt, f(t) = freq * r^(t/dur)
        phase = 2 * math.pi * freq * dur / lnr * (r ** (t / dur) - 1)
        if t < att:
            a = gain * t / att
        else:
            a = gain * (0.0008 / gain) ** ((t - att) / (dur - att))
        j = start + i
        if j < len(buf):
            buf[j] += a * math.sin(phase)


def click(buf, t0, gain, rng):
    """Шум 50 мс с exp-огибающей τ=8 мс, однополюсный highpass 3 кГц."""
    n = int(SR * 0.05)
    rc = 1 / (2 * math.pi * 3000)
    dt = 1 / SR
    alpha = rc / (rc + dt)
    start = int(t0 * SR)
    prev_x = prev_y = 0.0
    for i in range(n):
        x = (rng.random() * 2 - 1) * math.exp(-i / (SR * 0.008))
        y = alpha * (prev_y + x - prev_x)
        prev_x, prev_y = x, y
        j = start + i
        if j < len(buf):
            buf[j] += gain * y


def sakya(buf, t0, gain, rng):
    strike(buf, t0, 1040, gain, 5.5)
    strike(buf, t0, 1040 * 2.76, gain * 0.36, 3.0)
    click(buf, t0, 0.07, rng)


def normalize(buf):
    peak = max(abs(v) for v in buf) or 1.0
    target = 10 ** (PEAK_DBFS / 20)
    k = target / peak
    return [v * k for v in buf]


def write_wav(path, buf):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for v in buf:
            s = max(-32767, min(32767, int(round(v * 32767))))
            frames += struct.pack('<h', s)
        w.writeframes(bytes(frames))


def to_caf(wav, name):
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name)
    subprocess.run(['afconvert', '-f', 'caff', '-d', 'LEI16', wav, dst], check=True)
    print('wrote', os.path.normpath(dst))


def main():
    rng = random.Random(108)
    tmp = tempfile.mkdtemp(prefix='shama-bells-')

    start = [0.0] * int(SR * 5.6)
    sakya(start, 0.0, 0.22, rng)
    p = os.path.join(tmp, 'bell-start.wav'); write_wav(p, normalize(start)); to_caf(p, 'bell-start.caf')

    end = [0.0] * int(SR * (2.2 + 5.6))
    sakya(end, 0.0, 0.24, rng)
    sakya(end, 2.2, 0.18, rng)
    p = os.path.join(tmp, 'bell-end.wav'); write_wav(p, normalize(end)); to_caf(p, 'bell-end.caf')

    silence = [0.0] * int(SR * 2.0)
    p = os.path.join(tmp, 'silence.wav'); write_wav(p, silence); to_caf(p, 'silence.caf')


if __name__ == '__main__':
    sys.exit(main())
