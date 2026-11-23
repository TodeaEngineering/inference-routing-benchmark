# Inference routing benchmark: 20261115-compare-r1, 20261115-compare-r2, 20261115-compare-r3, 20261115-compare-r4, 20261115-compare-r5

Each figure is computed per run, then averaged: mean ± standard deviation, lowest to highest run in parentheses.

## shared-prefix

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time |
|---|---|---|---|---|
| service | 834 ms ± 52 ms (761 ms to 900 ms) | 1.75 s ± 143 ms (1.54 s to 1.90 s) | 42% ± 5% (37% to 47%) | 2.88 s ± 49 ms (2.80 s to 2.93 s) |
| kinference-tuned | 126 ms ± 5 ms (120 ms to 132 ms) | 161 ms ± 4 ms (157 ms to 168 ms) | 99% ± 0% (99% to 99%) | 1.87 s ± 12 ms (1.85 s to 1.88 s) |
| kinference | 125 ms ± 4 ms (123 ms to 129 ms) | 160 ms ± 0 ms (160 ms to 160 ms) | 99% ± 0% (99% to 99%) | 1.86 s ± 21 ms (1.83 s to 1.87 s) |
| llm-d-baseline | 121 ms ± 4 ms (115 ms to 125 ms) | 155 ms ± 6 ms (146 ms to 163 ms) | 99% ± 0% (99% to 99%) | 1.85 s ± 20 ms (1.82 s to 1.87 s) |
| llm-d-precise | 132 ms ± 4 ms (126 ms to 135 ms) | 162 ms ± 5 ms (158 ms to 170 ms) | 99% ± 0% (99% to 99%) | 1.87 s ± 26 ms (1.82 s to 1.89 s) |
| llm-d | 122 ms ± 2 ms (119 ms to 124 ms) | 150 ms ± 5 ms (146 ms to 155 ms) | 99% ± 0% (99% to 99%) | 1.85 s ± 37 ms (1.80 s to 1.87 s) |
| production-stack-prefix | 120 ms ± 4 ms (114 ms to 125 ms) | 147 ms ± 4 ms (144 ms to 154 ms) | 99% ± 0% (99% to 99%) | 1.85 s ± 27 ms (1.81 s to 1.88 s) |
| production-stack | 1.15 s ± 38 ms (1.11 s to 1.18 s) | 1.30 s ± 73 ms (1.24 s to 1.38 s) | 41% ± 5% (37% to 47%) | 3.01 s ± 9 ms (3.00 s to 3.01 s) |
| kthena-tuned | 119 ms ± 3 ms (114 ms to 123 ms) | 147 ms ± 1 ms (146 ms to 150 ms) | 99% ± 0% (99% to 99%) | 1.85 s ± 23 ms (1.83 s to 1.89 s) |
| kthena | 135 ms ± 1 ms (134 ms to 135 ms) | 1.18 s ± 21 ms (1.16 s to 1.21 s) | 84% ± 3% (82% to 88%) | 1.92 s ± 10 ms (1.91 s to 1.93 s) |
| dynamo-kv-tuned | 115 ms ± 3 ms (110 ms to 118 ms) | 155 ms ± 1 ms (154 ms to 156 ms) | 99% ± 0% (99% to 99%) | 1.86 s ± 5 ms (1.85 s to 1.86 s) |
| dynamo-kv | 785 ms ± 559 ms (139 ms to 1.11 s) | 1.22 s ± 9 ms (1.21 s to 1.23 s) | 51% ± 4% (48% to 56%) | 2.92 s ± 19 ms (2.90 s to 2.93 s) |
| dynamo | 1.03 s ± 246 ms (743 ms to 1.17 s) | 1.23 s ± 8 ms (1.22 s to 1.23 s) | 41% ± 6% (37% to 48%) | 3.00 s ± 25 ms (2.98 s to 3.03 s) |

## multi-turn

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time |
|---|---|---|---|---|
| service | 147 ms ± 9 ms (132 ms to 154 ms) | 590 ms ± 28 ms (548 ms to 618 ms) | 66% ± 1% (65% to 67%) | 1.67 s ± 47 ms (1.59 s to 1.71 s) |
| kinference-tuned | 94 ms ± 3 ms (91 ms to 98 ms) | 156 ms ± 6 ms (150 ms to 166 ms) | 94% ± 0% (94% to 94%) | 1.58 s ± 46 ms (1.50 s to 1.62 s) |
| kinference | 93 ms ± 1 ms (92 ms to 94 ms) | 157 ms ± 2 ms (155 ms to 160 ms) | 94% ± 0% (94% to 94%) | 1.59 s ± 29 ms (1.57 s to 1.62 s) |
| llm-d-baseline | 87 ms ± 1 ms (85 ms to 89 ms) | 150 ms ± 2 ms (148 ms to 153 ms) | 94% ± 0% (94% to 94%) | 1.53 s ± 46 ms (1.48 s to 1.60 s) |
| llm-d-precise | 97 ms ± 2 ms (95 ms to 100 ms) | 158 ms ± 5 ms (154 ms to 166 ms) | 94% ± 0% (94% to 94%) | 1.56 s ± 45 ms (1.51 s to 1.63 s) |
| llm-d | 86 ms ± 3 ms (85 ms to 90 ms) | 148 ms ± 5 ms (143 ms to 152 ms) | 94% ± 0% (94% to 94%) | 1.50 s ± 97 ms (1.39 s to 1.58 s) |
| production-stack-prefix | 85 ms ± 3 ms (82 ms to 88 ms) | 156 ms ± 7 ms (148 ms to 164 ms) | 94% ± 0% (94% to 94%) | 1.40 s ± 78 ms (1.30 s to 1.52 s) |
| production-stack | 147 ms ± 4 ms (143 ms to 150 ms) | 663 ms ± 4 ms (660 ms to 667 ms) | 69% ± 1% (68% to 70%) | 1.90 s ± 11 ms (1.88 s to 1.91 s) |
| kthena-tuned | 88 ms ± 3 ms (84 ms to 92 ms) | 151 ms ± 4 ms (146 ms to 156 ms) | 94% ± 0% (94% to 94%) | 1.58 s ± 23 ms (1.55 s to 1.61 s) |
| kthena | 118 ms ± 5 ms (114 ms to 123 ms) | 564 ms ± 45 ms (524 ms to 613 ms) | 82% ± 1% (81% to 83%) | 1.76 s ± 25 ms (1.73 s to 1.78 s) |
| dynamo-kv-tuned | 82 ms ± 4 ms (78 ms to 88 ms) | 146 ms ± 4 ms (140 ms to 150 ms) | 93% ± 0% (93% to 94%) | 1.63 s ± 55 ms (1.57 s to 1.68 s) |
| dynamo-kv | 119 ms ± 4 ms (117 ms to 123 ms) | 570 ms ± 17 ms (551 ms to 581 ms) | 81% ± 2% (78% to 82%) | 1.79 s ± 30 ms (1.76 s to 1.82 s) |
| dynamo | 136 ms ± 4 ms (133 ms to 141 ms) | 638 ms ± 27 ms (610 ms to 663 ms) | 68% ± 1% (67% to 70%) | 1.90 s ± 22 ms (1.88 s to 1.91 s) |

## control

| Stack | Median TTFT | p95 TTFT | Median total time |
|---|---|---|---|
| service | 1.15 s ± 9 ms (1.14 s to 1.16 s) | 2.18 s ± 73 ms (2.11 s to 2.29 s) | 3.78 s ± 51 ms (3.69 s to 3.82 s) |
| kinference-tuned | 1.23 s ± 22 ms (1.21 s to 1.26 s) | 1.89 s ± 173 ms (1.65 s to 2.03 s) | 3.99 s ± 12 ms (3.97 s to 4.00 s) |
| kinference | 1.22 s ± 10 ms (1.21 s to 1.23 s) | 1.85 s ± 146 ms (1.73 s to 2.01 s) | 3.99 s ± 18 ms (3.98 s to 4.01 s) |
| llm-d-baseline | 1.20 s ± 9 ms (1.19 s to 1.22 s) | 1.67 s ± 146 ms (1.41 s to 1.76 s) | 3.98 s ± 13 ms (3.96 s to 4.00 s) |
| llm-d-precise | 1.21 s ± 12 ms (1.20 s to 1.23 s) | 1.53 s ± 343 ms (1.24 s to 2.03 s) | 3.98 s ± 15 ms (3.96 s to 4.00 s) |
| llm-d | 1.44 s ± 114 ms (1.31 s to 1.51 s) | 2.41 s ± 334 ms (2.15 s to 2.78 s) | 3.49 s ± 39 ms (3.44 s to 3.51 s) |
| production-stack-prefix | 1.15 s ± 6 ms (1.14 s to 1.16 s) | 2.12 s ± 160 ms (1.89 s to 2.32 s) | 3.86 s ± 58 ms (3.76 s to 3.90 s) |
| production-stack | 1.42 s ± 70 ms (1.36 s to 1.50 s) | 1.76 s ± 15 ms (1.75 s to 1.78 s) | 3.99 s ± 15 ms (3.98 s to 4.01 s) |
| kthena-tuned | 1.22 s ± 17 ms (1.21 s to 1.25 s) | 1.94 s ± 156 ms (1.72 s to 2.11 s) | 3.99 s ± 9 ms (3.98 s to 4.00 s) |
| kthena | 1.21 s ± 9 ms (1.21 s to 1.22 s) | 2.13 s ± 129 ms (1.99 s to 2.22 s) | 3.99 s ± 12 ms (3.98 s to 4.00 s) |
| dynamo-kv-tuned | 1.48 s ± 12 ms (1.46 s to 1.49 s) | 1.76 s ± 16 ms (1.73 s to 1.77 s) | 3.99 s ± 17 ms (3.96 s to 4.01 s) |
| dynamo-kv | 1.48 s ± 9 ms (1.47 s to 1.49 s) | 1.76 s ± 17 ms (1.75 s to 1.78 s) | 3.99 s ± 16 ms (3.98 s to 4.01 s) |
| dynamo | 1.36 s ± 20 ms (1.35 s to 1.38 s) | 1.76 s ± 16 ms (1.75 s to 1.78 s) | 3.99 s ± 14 ms (3.98 s to 4.01 s) |

## pressure

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time |
|---|---|---|---|---|
| service | 1.26 s ± 11 ms (1.25 s to 1.28 s) | 3.32 s ± 139 ms (3.14 s to 3.51 s) | 13% ± 1% (12% to 14%) | 5.68 s ± 82 ms (5.57 s to 5.78 s) |
| kinference-tuned | 1.07 s ± 147 ms (834 ms to 1.20 s) | 1.55 s ± 54 ms (1.51 s to 1.64 s) | 51% ± 3% (47% to 55%) | 3.84 s ± 285 ms (3.46 s to 4.12 s) |
| llm-d-baseline | 980 ms ± 112 ms (884 ms to 1.16 s) | 2.42 s ± 67 ms (2.31 s to 2.47 s) | 52% ± 3% (47% to 55%) | 3.80 s ± 149 ms (3.60 s to 4.01 s) |
| llm-d-precise | 1.01 s ± 156 ms (875 ms to 1.18 s) | 1.39 s ± 107 ms (1.30 s to 1.55 s) | 51% ± 2% (49% to 53%) | 4.04 s ± 54 ms (4.00 s to 4.14 s) |
| production-stack-prefix | 782 ms ± 167 ms (496 ms to 908 ms) | 2.79 s ± 281 ms (2.40 s to 3.17 s) | 54% ± 2% (51% to 56%) | 3.70 s ± 189 ms (3.44 s to 3.97 s) |
| kthena-tuned | 1.01 s ± 85 ms (923 ms to 1.11 s) | 2.48 s ± 142 ms (2.38 s to 2.73 s) | 51% ± 1% (50% to 53%) | 3.91 s ± 137 ms (3.76 s to 4.11 s) |
| dynamo-kv-tuned | 1.24 s ± 8 ms (1.23 s to 1.24 s) | 1.59 s ± 254 ms (1.25 s to 1.78 s) | 33% ± 3% (27% to 35%) | 4.99 s ± 88 ms (4.88 s to 5.12 s) |

## burst

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time | Replicas per burst | Median TTFT in a burst | Cached share in a burst |
|---|---|---|---|---|---|---|---|
| service | 134 ms ± 21 ms (109 ms to 157 ms) | 957 ms ± 137 ms (765 ms to 1.10 s) | 87% ± 5% (81% to 91%) | 1.89 s ± 29 ms (1.85 s to 1.93 s) | 2.7 ± 0.1 (2.6 to 2.8) | 1.15 s ± 6 ms (1.14 s to 1.16 s) | 54% ± 1% (53% to 56%) |
| kinference-tuned | 136 ms ± 3 ms (131 ms to 141 ms) | 1.14 s ± 42 ms (1.09 s to 1.20 s) | 84% ± 1% (82% to 85%) | 1.93 s ± 11 ms (1.91 s to 1.94 s) | 3.0 ± 0.0 (3.0 to 3.0) | 1.17 s ± 7 ms (1.16 s to 1.18 s) | 50% ± 0% (50% to 50%) |
| llm-d-baseline | 124 ms ± 10 ms (112 ms to 132 ms) | 916 ms ± 422 ms (175 ms to 1.19 s) | 87% ± 6% (82% to 96%) | 1.93 s ± 58 ms (1.88 s to 2.03 s) | 2.8 ± 0.1 (2.6 to 2.9) | 1.15 s ± 7 ms (1.15 s to 1.16 s) | 53% ± 2% (52% to 56%) |
| llm-d-precise | 116 ms ± 12 ms (101 ms to 132 ms) | 333 ms ± 254 ms (178 ms to 769 ms) | 97% ± 4% (90% to 99%) | 1.81 s ± 130 ms (1.58 s to 1.89 s) | 1.5 ± 0.2 (1.3 to 1.7) | 492 ms ± 170 ms (409 ms to 795 ms) | 75% ± 3% (71% to 77%) |
| production-stack-prefix | 111 ms ± 12 ms (93 ms to 124 ms) | 166 ms ± 18 ms (135 ms to 176 ms) | 99% ± 0% (99% to 99%) | 1.75 s ± 260 ms (1.29 s to 1.88 s) | 1.0 ± 0.0 (1.0 to 1.0) | 388 ms ± 7 ms (381 ms to 398 ms) | 83% ± 0% (83% to 83%) |
| kthena-tuned | 134 ms ± 14 ms (116 ms to 153 ms) | 1.10 s ± 101 ms (935 ms to 1.18 s) | 82% ± 1% (80% to 84%) | 1.93 s ± 22 ms (1.90 s to 1.96 s) | 3.0 ± 0.0 (3.0 to 3.0) | 1.15 s ± 7 ms (1.15 s to 1.16 s) | 50% ± 0% (50% to 50%) |
| dynamo-kv-tuned | 133 ms ± 3 ms (128 ms to 135 ms) | 1.14 s ± 50 ms (1.08 s to 1.20 s) | 83% ± 2% (80% to 85%) | 1.93 s ± 16 ms (1.90 s to 1.94 s) | 3.0 ± 0.0 (3.0 to 3.0) | 1.15 s ± 8 ms (1.14 s to 1.16 s) | 50% ± 0% (50% to 50%) |

## mixed

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time | Median TTFT, long requests |
|---|---|---|---|---|---|
| service | 97 ms ± 6 ms (92 ms to 107 ms) | 651 ms ± 92 ms (530 ms to 790 ms) | 7% ± 1% (6% to 8%) | 624 ms ± 4 ms (620 ms to 627 ms) | 969 ms ± 21 ms (947 ms to 1.00 s) |
| kinference-tuned | 133 ms ± 4 ms (128 ms to 137 ms) | 177 ms ± 3 ms (172 ms to 181 ms) | 7% ± 1% (6% to 8%) | 695 ms ± 9 ms (682 ms to 704 ms) | 1.10 s ± 31 ms (1.06 s to 1.13 s) |
| llm-d-baseline | 108 ms ± 3 ms (104 ms to 112 ms) | 138 ms ± 2 ms (136 ms to 140 ms) | 7% ± 1% (6% to 8%) | 657 ms ± 9 ms (647 ms to 665 ms) | 1.09 s ± 18 ms (1.06 s to 1.10 s) |
| llm-d-precise | 108 ms ± 9 ms (96 ms to 120 ms) | 139 ms ± 3 ms (135 ms to 144 ms) | 7% ± 1% (6% to 8%) | 645 ms ± 20 ms (621 ms to 677 ms) | 1.07 s ± 21 ms (1.05 s to 1.10 s) |
| production-stack-prefix | 95 ms ± 6 ms (91 ms to 105 ms) | 730 ms ± 147 ms (522 ms to 875 ms) | 7% ± 1% (6% to 8%) | 630 ms ± 19 ms (609 ms to 658 ms) | 1.00 s ± 23 ms (966 ms to 1.02 s) |
| kthena-tuned | 117 ms ± 6 ms (111 ms to 126 ms) | 847 ms ± 104 ms (695 ms to 954 ms) | 7% ± 1% (6% to 8%) | 675 ms ± 8 ms (666 ms to 688 ms) | 1.12 s ± 8 ms (1.11 s to 1.14 s) |
| dynamo-kv-tuned | 121 ms ± 1 ms (120 ms to 123 ms) | 141 ms ± 2 ms (139 ms to 144 ms) | 7% ± 1% (6% to 8%) | 682 ms ± 1 ms (681 ms to 684 ms) | 1.14 s ± 5 ms (1.13 s to 1.14 s) |

## rate-sweep

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time | Failed requests | 1/s median | 1/s p95 | 1/s achieved | 2/s median | 2/s p95 | 2/s achieved | 3/s median | 3/s p95 | 3/s failed | 3/s achieved | 4/s median | 4/s p95 | 4/s achieved | 6/s median | 6/s p95 | 6/s failed | 6/s achieved |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| service | 1.45 s ± 147 ms (1.29 s to 1.58 s) | 8.88 s ± 1.56 s (7.13 s to 10.12 s) | 52% ± 0% (52% to 52%) | 6.69 s ± 1.07 s (5.99 s to 7.91 s) | 0.0 ± 0.0 (0.0 to 0.0) | 363 ms ± 1 ms (361 ms to 364 ms) | 1.09 s ± 132 ms (997 ms to 1.24 s) | 1.0 ± 0.1 (0.8 to 1.1) | 735 ms ± 165 ms (612 ms to 923 ms) | 2.10 s ± 292 ms (1.82 s to 2.41 s) | 2.1 ± 0.1 (1.9 to 2.2) | 1.09 s ± 388 ms (815 ms to 1.54 s) | 3.42 s ± 1.30 s (2.27 s to 4.82 s) | 0.0 ± 0.0 (0.0 to 0.0) | 3.0 ± 0.3 (2.7 to 3.3) | 1.55 s ± 84 ms (1.49 s to 1.65 s) | 5.74 s ± 680 ms (5.19 s to 6.50 s) | 3.6 ± 0.2 (3.5 to 3.7) | 4.34 s ± 1.43 s (2.71 s to 5.39 s) | 10.22 s ± 1.51 s (8.62 s to 11.62 s) | 34.3 ± 17.2 (19.0 to 53.0) | 4.3 ± 0.3 (4.1 to 4.6) |
| kinference-tuned | 132 ms ± 2 ms (130 ms to 134 ms) | 172 ms ± 3 ms (169 ms to 175 ms) | 99% ± 0% (99% to 99%) | 1.88 s ± 13 ms (1.86 s to 1.88 s) | 0.0 ± 0.0 (0.0 to 0.0) | 51 ms ± 5 ms (47 ms to 56 ms) | 105 ms ± 20 ms (93 ms to 128 ms) | 1.0 ± 0.1 (0.8 to 1.1) | 79 ms ± 10 ms (68 ms to 88 ms) | 151 ms ± 5 ms (145 ms to 155 ms) | 2.1 ± 0.1 (2.0 to 2.2) | 119 ms ± 13 ms (110 ms to 134 ms) | 155 ms ± 4 ms (151 ms to 159 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 3.0 ± 0.4 (2.8 to 3.5) | 135 ms ± 4 ms (132 ms to 139 ms) | 166 ms ± 5 ms (161 ms to 172 ms) | 3.8 ± 0.1 (3.6 to 3.9) | 144 ms ± 2 ms (142 ms to 146 ms) | 180 ms ± 1 ms (178 ms to 181 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 5.6 ± 0.2 (5.4 to 5.8) |
| llm-d-baseline | 123 ms ± 2 ms (122 ms to 125 ms) | 164 ms ± 5 ms (159 ms to 168 ms) | 99% ± 0% (99% to 99%) | 1.88 s ± 22 ms (1.86 s to 1.90 s) | 0.0 ± 0.0 (0.0 to 0.0) | 41 ms ± 4 ms (37 ms to 46 ms) | 124 ms ± 5 ms (119 ms to 127 ms) | 1.0 ± 0.1 (0.8 to 1.1) | 73 ms ± 13 ms (58 ms to 82 ms) | 141 ms ± 2 ms (139 ms to 143 ms) | 2.1 ± 0.2 (2.0 to 2.3) | 116 ms ± 5 ms (112 ms to 121 ms) | 151 ms ± 4 ms (147 ms to 154 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 3.0 ± 0.4 (2.8 to 3.5) | 122 ms ± 0 ms (122 ms to 123 ms) | 155 ms ± 6 ms (150 ms to 161 ms) | 3.8 ± 0.1 (3.6 to 3.9) | 137 ms ± 1 ms (136 ms to 139 ms) | 174 ms ± 6 ms (168 ms to 179 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 5.7 ± 0.2 (5.5 to 5.8) |
| llm-d-precise | 133 ms ± 0 ms (132 ms to 133 ms) | 175 ms ± 0 ms (175 ms to 176 ms) | 99% ± 0% (99% to 99%) | 1.89 s ± 17 ms (1.87 s to 1.91 s) | 0.0 ± 0.0 (0.0 to 0.0) | 49 ms ± 1 ms (48 ms to 49 ms) | 108 ms ± 10 ms (99 ms to 118 ms) | 1.0 ± 0.1 (0.8 to 1.1) | 82 ms ± 12 ms (69 ms to 92 ms) | 157 ms ± 6 ms (152 ms to 163 ms) | 2.1 ± 0.2 (1.9 to 2.2) | 118 ms ± 14 ms (102 ms to 127 ms) | 163 ms ± 4 ms (159 ms to 168 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 3.1 ± 0.4 (2.8 to 3.5) | 135 ms ± 1 ms (134 ms to 136 ms) | 164 ms ± 5 ms (159 ms to 168 ms) | 3.8 ± 0.1 (3.6 to 3.9) | 147 ms ± 2 ms (144 ms to 149 ms) | 184 ms ± 0 ms (184 ms to 185 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 5.7 ± 0.2 (5.4 to 5.8) |
| production-stack-prefix | 121 ms ± 6 ms (115 ms to 126 ms) | 165 ms ± 3 ms (162 ms to 167 ms) | 99% ± 0% (99% to 99%) | 1.82 s ± 72 ms (1.74 s to 1.89 s) | 0.3 ± 0.6 (0.0 to 1.0) | 40 ms ± 3 ms (37 ms to 43 ms) | 100 ms ± 19 ms (89 ms to 121 ms) | 1.0 ± 0.1 (0.8 to 1.1) | 67 ms ± 12 ms (58 ms to 81 ms) | 141 ms ± 4 ms (138 ms to 145 ms) | 2.1 ± 0.1 (2.0 to 2.3) | 102 ms ± 22 ms (87 ms to 128 ms) | 149 ms ± 5 ms (144 ms to 155 ms) | 0.3 ± 0.6 (0.0 to 1.0) | 3.0 ± 0.4 (2.8 to 3.5) | 124 ms ± 1 ms (124 ms to 125 ms) | 158 ms ± 7 ms (151 ms to 163 ms) | 3.8 ± 0.1 (3.7 to 3.9) | 134 ms ± 6 ms (127 ms to 137 ms) | 174 ms ± 5 ms (171 ms to 180 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 5.7 ± 0.1 (5.5 to 5.8) |
| kthena-tuned | 121 ms ± 2 ms (119 ms to 123 ms) | 162 ms ± 2 ms (159 ms to 164 ms) | 99% ± 0% (99% to 99%) | 1.87 s ± 22 ms (1.85 s to 1.89 s) | 0.0 ± 0.0 (0.0 to 0.0) | 39 ms ± 3 ms (36 ms to 42 ms) | 97 ms ± 6 ms (92 ms to 104 ms) | 1.0 ± 0.1 (0.8 to 1.1) | 82 ms ± 6 ms (78 ms to 90 ms) | 143 ms ± 3 ms (140 ms to 146 ms) | 2.1 ± 0.2 (2.0 to 2.3) | 107 ms ± 14 ms (91 ms to 117 ms) | 147 ms ± 3 ms (144 ms to 150 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 3.0 ± 0.4 (2.8 to 3.5) | 120 ms ± 4 ms (117 ms to 125 ms) | 153 ms ± 3 ms (150 ms to 156 ms) | 3.8 ± 0.1 (3.7 to 3.9) | 137 ms ± 0 ms (137 ms to 137 ms) | 177 ms ± 10 ms (171 ms to 189 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 5.6 ± 0.2 (5.4 to 5.8) |
| dynamo-kv-tuned | 117 ms ± 1 ms (116 ms to 118 ms) | 163 ms ± 4 ms (159 ms to 167 ms) | 99% ± 0% (99% to 99%) | 1.88 s ± 14 ms (1.86 s to 1.89 s) | 0.0 ± 0.0 (0.0 to 0.0) | 32 ms ± 1 ms (32 ms to 33 ms) | 80 ms ± 24 ms (54 ms to 102 ms) | 1.0 ± 0.1 (0.8 to 1.1) | 70 ms ± 11 ms (58 ms to 78 ms) | 133 ms ± 1 ms (132 ms to 134 ms) | 2.2 ± 0.2 (2.0 to 2.3) | 104 ms ± 16 ms (86 ms to 117 ms) | 146 ms ± 8 ms (138 ms to 154 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 3.0 ± 0.4 (2.8 to 3.5) | 121 ms ± 4 ms (116 ms to 123 ms) | 163 ms ± 3 ms (160 ms to 166 ms) | 3.8 ± 0.1 (3.6 to 3.9) | 131 ms ± 1 ms (129 ms to 132 ms) | 169 ms ± 6 ms (164 ms to 176 ms) | 0.0 ± 0.0 (0.0 to 0.0) | 5.6 ± 0.2 (5.4 to 5.8) |

## replica-restart

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time | Failed requests | Cached share before | Cached share, last minute |
|---|---|---|---|---|---|---|---|
| service | 666 ms ± 158 ms (484 ms to 764 ms) | 1.55 s ± 129 ms (1.46 s to 1.70 s) | 52% ± 3% (51% to 55%) | 2.37 s ± 98 ms (2.26 s to 2.44 s) | 0.0 ± 0.0 (0.0 to 0.0) | 52% ± 3% (49% to 55%) | 52% ± 10% (42% to 62%) |
| kinference-tuned | 97 ms ± 1 ms (95 ms to 97 ms) | 139 ms ± 3 ms (137 ms to 142 ms) | 98% ± 0% (98% to 98%) | 1.31 s ± 3 ms (1.31 s to 1.31 s) | 0.3 ± 0.6 (0.0 to 1.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |
| llm-d-baseline | 92 ms ± 0 ms (91 ms to 92 ms) | 315 ms ± 326 ms (125 ms to 692 ms) | 97% ± 2% (94% to 98%) | 1.31 s ± 7 ms (1.30 s to 1.31 s) | 0.0 ± 0.0 (0.0 to 0.0) | 99% ± 0% (99% to 99%) | 97% ± 3% (94% to 99%) |
| llm-d-precise | 101 ms ± 1 ms (99 ms to 102 ms) | 147 ms ± 9 ms (137 ms to 155 ms) | 98% ± 0% (97% to 98%) | 1.31 s ± 6 ms (1.31 s to 1.32 s) | 0.0 ± 0.0 (0.0 to 0.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |
| production-stack-prefix | 92 ms ± 0 ms (91 ms to 92 ms) | 398 ms ± 286 ms (130 ms to 699 ms) | 96% ± 2% (94% to 98%) | 1.31 s ± 6 ms (1.30 s to 1.31 s) | 0.7 ± 0.6 (0.0 to 1.0) | 99% ± 1% (98% to 99%) | 97% ± 2% (95% to 99%) |
| kthena-tuned | 92 ms ± 0 ms (91 ms to 92 ms) | 159 ms ± 29 ms (129 ms to 187 ms) | 97% ± 1% (96% to 98%) | 1.31 s ± 7 ms (1.30 s to 1.31 s) | 0.3 ± 0.6 (0.0 to 1.0) | 99% ± 0% (99% to 99%) | 98% ± 1% (98% to 99%) |
| dynamo-kv-tuned | 89 ms ± 0 ms (89 ms to 90 ms) | 316 ms ± 302 ms (136 ms to 665 ms) | 96% ± 1% (95% to 97%) | 1.31 s ± 8 ms (1.30 s to 1.32 s) | 0.0 ± 0.0 (0.0 to 0.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |

## router-restart

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time | Failed requests | Cached share before | Cached share, last minute |
|---|---|---|---|---|---|---|---|
| kinference-tuned | 129 ms ± 2 ms (127 ms to 130 ms) | 1.01 s ± 58 ms (972 ms to 1.08 s) | 94% ± 0% (94% to 94%) | 1.85 s ± 15 ms (1.83 s to 1.86 s) | 8.7 ± 2.9 (7.0 to 12.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |
| llm-d-baseline | 118 ms ± 2 ms (116 ms to 119 ms) | 185 ms ± 26 ms (168 ms to 215 ms) | 96% ± 1% (95% to 96%) | 1.83 s ± 17 ms (1.81 s to 1.85 s) | 66.0 ± 0.0 (66.0 to 66.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |
| llm-d-precise | 124 ms ± 2 ms (122 ms to 126 ms) | 159 ms ± 1 ms (158 ms to 160 ms) | 99% ± 0% (99% to 99%) | 1.85 s ± 6 ms (1.85 s to 1.86 s) | 66.0 ± 0.0 (66.0 to 66.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |
| production-stack-prefix | 119 ms ± 4 ms (115 ms to 122 ms) | 1.13 s ± 28 ms (1.10 s to 1.16 s) | 91% ± 0% (91% to 91%) | 1.85 s ± 14 ms (1.84 s to 1.86 s) | 46.7 ± 5.0 (42.0 to 52.0) | 99% ± 0% (99% to 99%) | 83% ± 1% (82% to 84%) |
| kthena-tuned | 123 ms ± 5 ms (117 ms to 126 ms) | 1.17 s ± 3 ms (1.17 s to 1.17 s) | 89% ± 1% (88% to 90%) | 1.87 s ± 1 ms (1.87 s to 1.87 s) | 12.0 ± 0.0 (12.0 to 12.0) | 99% ± 0% (99% to 99%) | 79% ± 1% (78% to 80%) |
| dynamo-kv-tuned | 107 ms ± 8 ms (98 ms to 114 ms) | 148 ms ± 5 ms (142 ms to 153 ms) | 99% ± 0% (99% to 99%) | 1.82 s ± 52 ms (1.76 s to 1.86 s) | 16.3 ± 1.5 (15.0 to 18.0) | 99% ± 0% (99% to 99%) | 99% ± 0% (99% to 99%) |

## overhead

| Stack | Median TTFT | p95 TTFT | Cached share | Median total time | Added, median | Added, p95 |
|---|---|---|---|---|---|---|
| service | 14 ms ± 0 ms (14 ms to 14 ms) | 15 ms ± 0 ms (15 ms to 15 ms) | 25% ± 0% (25% to 25%) | 14 ms ± 0 ms (14 ms to 14 ms) | 0 ms ± 0 ms (0 ms to 0 ms) | 1 ms ± 0 ms (1 ms to 1 ms) |
| kinference-tuned | 57 ms ± 0 ms (56 ms to 57 ms) | 58 ms ± 0 ms (58 ms to 58 ms) | 25% ± 0% (25% to 25%) | 57 ms ± 0 ms (56 ms to 57 ms) | 42 ms ± 0 ms (42 ms to 42 ms) | 44 ms ± 0 ms (43 ms to 44 ms) |
| llm-d-baseline | 15 ms ± 0 ms (15 ms to 15 ms) | 17 ms ± 0 ms (17 ms to 17 ms) | 25% ± 0% (25% to 25%) | 15 ms ± 0 ms (15 ms to 15 ms) | 1 ms ± 0 ms (1 ms to 1 ms) | 2 ms ± 0 ms (2 ms to 3 ms) |
| llm-d-precise | 17 ms ± 0 ms (16 ms to 17 ms) | 19 ms ± 0 ms (19 ms to 19 ms) | 25% ± 0% (25% to 25%) | 17 ms ± 0 ms (16 ms to 17 ms) | 2 ms ± 0 ms (2 ms to 2 ms) | 4 ms ± 0 ms (4 ms to 5 ms) |
| production-stack-prefix | 15 ms ± 0 ms (14 ms to 15 ms) | 16 ms ± 0 ms (16 ms to 16 ms) | 25% ± 0% (25% to 25%) | 15 ms ± 0 ms (14 ms to 15 ms) | 0 ms ± 0 ms (0 ms to 0 ms) | 2 ms ± 0 ms (1 ms to 2 ms) |
| kthena-tuned | 14 ms ± 0 ms (14 ms to 14 ms) | 16 ms ± 0 ms (15 ms to 16 ms) | 25% ± 0% (25% to 25%) | 14 ms ± 0 ms (14 ms to 14 ms) | 0 ms ± 0 ms (0 ms to 0 ms) | 1 ms ± 0 ms (1 ms to 1 ms) |
| dynamo-kv-tuned | 14 ms ± 0 ms (14 ms to 14 ms) | 14 ms ± 0 ms (14 ms to 14 ms) | 25% ± 0% (25% to 25%) | 14 ms ± 0 ms (14 ms to 14 ms) | n/a | n/a |

## Router footprint

CPU and memory of the pods each stack adds: mean CPU and peak memory per workload, averaged over workloads and runs.

| Stack | CPU idle, millicores | CPU under load, millicores | Memory under load, MiB |
|---|---|---|---|
| kinference-tuned | 2.9 ± 0.4 (2.0 to 3.8) | 10.9 ± 2.4 (5.7 to 16.3) | 28.8 ± 5.2 (18.0 to 35.0) |
| kinference | 3.0 ± 0.4 (2.5 to 3.5) | 10.1 ± 0.5 (9.4 to 10.7) | 23.4 ± 3.1 (20.0 to 28.0) |
| llm-d-baseline | 10.7 ± 2.3 (6.2 to 17.4) | 41.2 ± 7.5 (23.5 to 56.5) | 58.3 ± 5.0 (51.0 to 82.0) |
| llm-d-precise | 11.0 ± 2.0 (6.8 to 17.0) | 47.7 ± 10.3 (24.0 to 67.4) | 101.6 ± 25.7 (64.0 to 170.0) |
| llm-d | 16.6 ± 2.0 (12.4 to 18.8) | 44.7 ± 2.2 (41.6 to 47.7) | 86.7 ± 5.2 (80.0 to 93.0) |
| production-stack-prefix | 1.5 ± 0.2 (1.2 to 2.0) | 15.5 ± 32.5 (1.0 to 167.0) | 712.2 ± 19.9 (682.0 to 740.0) |
| production-stack | 1.6 ± 0.2 (1.4 to 2.0) | 5.7 ± 0.7 (4.9 to 6.6) | 682.1 ± 2.2 (680.0 to 685.0) |
| kthena-tuned | 2.6 ± 0.6 (1.6 to 4.2) | 9.8 ± 1.8 (6.0 to 13.8) | 28.2 ± 6.4 (18.0 to 47.0) |
| kthena | 2.6 ± 0.4 (2.2 to 3.4) | 9.6 ± 0.8 (8.5 to 10.6) | 32.2 ± 11.1 (24.0 to 48.0) |
| dynamo-kv-tuned | 15.3 ± 4.7 (5.2 to 28.2) | 19.3 ± 7.9 (4.0 to 40.9) | 457.5 ± 91.6 (311.0 to 622.0) |
| dynamo-kv | 16.6 ± 5.2 (9.2 to 24.5) | 16.8 ± 2.7 (12.2 to 21.0) | 386.7 ± 26.4 (344.0 to 418.0) |
| dynamo | 15.2 ± 3.8 (9.0 to 20.5) | 14.0 ± 5.5 (3.0 to 19.9) | 360.4 ± 28.8 (315.0 to 392.0) |
