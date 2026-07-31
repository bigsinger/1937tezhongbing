# MOD 12-Level Isolated Regression Report

The probe posts only to the tested game window and the process-local DirectInput proxy. It never calls global cursor, input, or focus APIs.

| Level | Route | Result | Stages | CPU% | Read | Compositor P95/P99 | Unresponsive | Cursor clipped |
|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 01 | 1 | pass | 16 | 14.3 | 24408697 | 7.73/14.07 ms | 0 | 0 |
| 02 | 2 | pass | 16 | 12.2 | 21000677 | 7.49/10.69 ms | 0 | 0 |
| 03 | 3 | pass | 16 | 13.0 | 18027269 | 7.47/11.89 ms | 0 | 0 |
| 04 | 4 | pass | 16 | 11.6 | 23235421 | 7.35/10.40 ms | 0 | 0 |
| 05 | 5 | pass | 16 | 30.7 | 26221577 | 7.61/13.20 ms | 0 | 0 |
| 06 | 6 | pass | 16 | 12.9 | 21907001 | 7.58/10.27 ms | 0 | 0 |
| 07 | 7 | pass | 16 | 14.2 | 22520177 | 7.93/12.26 ms | 0 | 0 |
| 08 | 8 | pass | 16 | 14.0 | 24075721 | 7.35/8.44 ms | 0 | 0 |
| 09 | 9 | pass | 16 | 8.4 | 17936377 | 7.42/10.80 ms | 0 | 0 |
| 10 | 10 | pass | 16 | 18.3 | 21231601 | 7.51/12.81 ms | 0 | 0 |
| 11 | 11 | pass | 16 | 15.0 | 19858813 | 7.75/9.31 ms | 0 | 0 |
| 12 | 12 | pass | 16 | 15.3 | 21592653 | 7.75/11.27 ms | 0 | 0 |

| Level | Alert | Reaction max | Reinforcements | Searches/replans | Escape | AI tick max | Live target |
|---:|---|---:|---:|---:|---:|---:|---|
| 01 | yes | 281 ms | 3 | 3/12 | 3/3 | 382 us | no |
| 02 | yes | 344 ms | 2 | 2/8 | 2/2 | 443 us | no |
| 03 | yes | 313 ms | 3 | 3/12 | 3/3 | 254 us | no |
| 04 | yes | 297 ms | 3 | 3/12 | 3/3 | 331 us | no |
| 05 | yes | 344 ms | 3 | 3/12 | 3/3 | 423 us | no |
| 06 | yes | 297 ms | 3 | 3/12 | 3/3 | 231 us | no |
| 07 | yes | 344 ms | 3 | 3/12 | 3/3 | 652 us | no |
| 08 | yes | 328 ms | 3 | 3/12 | 3/3 | 1325 us | no |
| 09 | yes | 250 ms | 3 | 3/12 | 3/3 | 101 us | no |
| 10 | yes | 297 ms | 3 | 3/12 | 3/3 | 870 us | no |
| 11 | yes | 312 ms | 3 | 6/0 | 3/3 | 190 us | no |
| 12 | yes | 328 ms | 3 | 3/12 | 3/3 | 236 us | no |

AI aggregate: escape 35/35 (100.0%); maximum reaction 344 ms; maximum reinforcements 3; live target sampling after alert: False.

Overall: pass
