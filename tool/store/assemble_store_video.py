#!/usr/bin/env python3
"""Cuts a store video from the frames of integration_test/store_video_test.dart.

    python3 tool/store/assemble_store_video.py <frames_dir> <cut> <w>x<h> <out.mp4> [crop]

<frames_dir> holds one folder per scene (PNG frames + times.txt with each
frame's game time). <cut> is `preview` (App Preview, under 30 s) or `youtube`
(the longer promo) or `header` (the App Store product page header / search
results loop, flights only). `crop` fills <w>x<h> and cuts the overflow
(the header's 21:9 and 3:2 from 16:9 frames) instead of letterboxing. Each segment takes [start, start + length) seconds of a
scene's game time; frames keep their own durations, so the slow-motion capture
plays back at real speed, resampled to a constant 30 fps. A silent stereo
track is added (the App Store wants audio). Needs ffmpeg (FFMPEG overrides the
binary).
"""
import os
import subprocess
import sys

FFMPEG = os.environ.get('FFMPEG', 'ffmpeg')
BG = '0x0B132B'  # game backdrop: letterbox colour

# (scene, start s, length s). A missing scene is skipped.
# The exp_00 demo replay glitches at its first leg switch (the pod jumps
# off the tow ~5.5 s into the `expedition` scene), so that scene ends at 5.3 s.
CUTS = {
    # App Store App Preview: 15–30 s, opens on flight.
    'preview': [
        ('alien', 1.0, 4.5),
        ('mine', 1.0, 3.5),
        ('radio', 4.0, 4.0),
        ('orbit', 1.0, 3.5),
        ('redoubt', 1.5, 4.5),
        ('lava', 2.0, 3.0),
        ('expedition', 2.0, 3.3),
        ('complete', 0.5, 2.5),
    ],
    # App Store product page header / search results: a ~13 s silent loop
    # of flights (HUD-free `header` frames).
    'header': [
        ('orbit', 1.0, 4.5),
        ('lava', 2.0, 4.0),
        ('redoubt', 1.5, 4.5),
    ],
    # YouTube / Play promo, ~75 s, the whole tour.
    'youtube': [
        ('intro', 0.0, 2.0),
        ('alien', 0.0, 6.0),
        ('missions', 0.3, 3.5),
        ('chapter', 0.5, 4.5),
        ('chapter2', 0.3, 3.5),
        ('briefing', 0.3, 4.0),
        ('radio', 0.5, 6.5),
        ('orbit', 0.0, 5.0),
        ('mine', 0.0, 5.5),
        ('ice', 0.0, 5.0),
        ('lava', 0.0, 5.5),
        ('redoubt', 0.0, 7.0),
        ('expedition', 0.0, 5.3),
        ('complete', 0.3, 3.5),
        ('garage', 0.3, 4.0),
        ('hangar', 0.3, 3.5),
    ],
}


def frames(scene_dir):
    with open(os.path.join(scene_dir, 'times.txt')) as f:
        times = [float(t) for t in f.read().split()]
    return [(t, os.path.join(scene_dir, 'f_%05d.png' % i)) for i, t in enumerate(times)]


def concat_list(root, cut):
    lines, total = [], 0.0
    for scene, start, length in CUTS[cut]:
        d = os.path.join(root, scene)
        if not os.path.isfile(os.path.join(d, 'times.txt')):
            print('skip %s (not captured)' % scene, file=sys.stderr)
            continue
        fs = frames(d)
        # The frame on screen at `start`, then every frame up to the end.
        first = max((i for i, (t, _) in enumerate(fs) if t <= start), default=0)
        end = start + length
        picked = [(max(t, start), p) for t, p in fs[first:] if t < end]
        for k, (t, p) in enumerate(picked):
            nxt = picked[k + 1][0] if k + 1 < len(picked) else end
            lines.append("file '%s'\nduration %.4f" % (p, nxt - t))
        total += end - start
    # The concat demuxer ignores the last duration unless the file repeats.
    last = lines[-1].split('\n')[0]
    lines.append(last)
    return '\n'.join(lines) + '\n', total


def main():
    root, cut, size, out = sys.argv[1:5]
    crop = len(sys.argv) > 5 and sys.argv[5] == 'crop'
    root = os.path.abspath(root)
    w, h = size.split('x')
    text, total = concat_list(root, cut)
    listing = os.path.abspath(out) + '.frames.txt'
    with open(listing, 'w') as f:
        f.write(text)
    fit = ('scale=%s:%s:force_original_aspect_ratio=increase,crop=%s:%s' % (w, h, w, h)
           if crop else
           'scale=%s:%s:force_original_aspect_ratio=decrease,'
           'pad=%s:%s:(ow-iw)/2:(oh-ih)/2:color=%s' % (w, h, w, h, BG))
    vf = ('fps=30,%s,setsar=1,'
          'fade=t=in:st=0:d=0.3,fade=t=out:st=%.2f:d=0.4,format=yuv420p'
          % (fit, max(0.0, total - 0.4)))
    # 4K (the header art) needs level 5.1 and more bits than 1080p.
    big = int(w) * int(h) > 2048 * 1080
    level, rate, maxrate = ('5.1', '30M', '36M') if big else ('4.0', '10M', '12M')
    subprocess.run([
        FFMPEG, '-y', '-v', 'error',
        '-f', 'concat', '-safe', '0', '-i', listing,
        '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
        '-map', '0:v:0', '-map', '1:a:0', '-t', '%.3f' % total,
        '-vf', vf,
        '-c:v', 'libx264', '-profile:v', 'high', '-level', level,
        '-b:v', rate, '-maxrate', maxrate, '-bufsize', '60M',
        '-c:a', 'aac', '-b:a', '256k', '-ar', '44100', '-ac', '2',
        '-movflags', '+faststart', out,
    ], check=True)
    os.unlink(listing)
    print('%s  %.1f s  %s' % (out, total, size))


if __name__ == '__main__':
    main()
