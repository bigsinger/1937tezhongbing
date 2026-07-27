# MOD 15-Level Isolated Regression Report

The probe posts only to the tested game window and the process-local DirectInput proxy. It never calls global cursor, input, or focus APIs.

| Level | Route | Result | Stages | CPU% | Read | Compositor P95/P99 | Unresponsive | Cursor clipped |
|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 01 | 1 | pass | 10 | 5.4 | 24090745 | 7.58/8.88 ms | 0 | 0 |
| 02 | 2 | pass | 10 | 5.8 | 20344293 | 7.62/9.09 ms | 0 | 0 |
| 03 | 3 | pass | 10 | 4.9 | 17613061 | 7.40/9.26 ms | 0 | 0 |
| 04 | 4 | pass | 10 | 7.0 | 23053149 | 7.75/8.98 ms | 0 | 0 |
| 05 | 5 | pass | 10 | 9.2 | 24601097 | 7.93/13.05 ms | 0 | 0 |
| 06 | 6 | pass | 10 | 6.0 | 21866041 | 7.50/8.63 ms | 0 | 0 |
| 07 | 7 | pass | 10 | 5.8 | 21895537 | 7.75/8.77 ms | 0 | 0 |
| 08 | 8 | pass | 10 | 8.6 | 20657097 | 7.87/10.43 ms | 0 | 0 |
| 09 | 9 | pass | 10 | 6.2 | 17918969 | 7.80/9.15 ms | 0 | 0 |
| 10 | 10 | pass | 10 | 9.5 | 20778993 | 7.86/9.46 ms | 0 | 0 |
| 11 | 11 | pass | 10 | 8.9 | 20066173 | 7.85/11.09 ms | 0 | 0 |
| 12 | 12 | pass | 10 | 10.4 | 11290344 | 7.76/8.63 ms | 0 | 0 |
| 13 | 12 | pass | 10 | 10.7 | 19951181 | 7.93/8.91 ms | 0 | 0 |
| 14 | 7 | pass | 10 | 11.0 | 21697393 | 8.08/11.11 ms | 0 | 0 |
| 15 | 7 | pass | 10 | 12.5 | 21138801 | 7.96/10.70 ms | 0 | 0 |

| Level | Alert | Reaction max | Reinforcements | Searches/replans | Escape | AI tick max | Live target |
|---:|---|---:|---:|---:|---:|---:|---|
| 01 | yes | 328 ms | 3 | 3/12 | 3/3 | 227 us | no |
| 02 | yes | 344 ms | 3 | 3/12 | 3/3 | 249 us | no |
| 03 | yes | 329 ms | 3 | 3/12 | 3/3 | 125 us | no |
| 04 | yes | 312 ms | 3 | 3/12 | 3/3 | 393 us | no |
| 05 | yes | 296 ms | 2 | 2/8 | 2/2 | 129 us | no |
| 06 | yes | 250 ms | 3 | 3/12 | 3/3 | 309 us | no |
| 07 | yes | 297 ms | 3 | 3/12 | 3/3 | 82 us | no |
| 08 | yes | 344 ms | 3 | 3/12 | 3/3 | 620 us | no |
| 09 | yes | 266 ms | 3 | 3/12 | 3/3 | 108 us | no |
| 10 | yes | 328 ms | 3 | 3/12 | 3/3 | 418 us | no |
| 11 | yes | 266 ms | 3 | 3/12 | 3/3 | 614 us | no |
| 12 | yes | 250 ms | 3 | 3/12 | 3/3 | 303 us | no |
| 13 | yes | 265 ms | 3 | 3/12 | 3/3 | 231 us | no |
| 14 | yes | 281 ms | 3 | 3/12 | 3/3 | 565 us | no |
| 15 | yes | 266 ms | 3 | 3/12 | 3/3 | 292 us | no |

AI aggregate: escape 44/44 (100.0%); maximum reaction 344 ms; maximum reinforcements 3; live target sampling after alert: False.

Overall: pass
