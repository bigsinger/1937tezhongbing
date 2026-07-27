# MOD 1-Minute Performance Baseline

Input is posted only to the isolated game window and consumed by the process-local DirectInput proxy. System cursor calls: 0.

The probe deliberately does not foreground the game. Cursor spans prove client-edge input delivery; foreground scroll movement is covered by the separate v1.3.7 real-mouse visual regression.

| Profile | Result | Level | CPU% | P95/P99 | >25/>50 ms | Input max | Pump max | Log drop | Cursor clipped | Disk first/steady | Cursor X/Y | Camera X/Y | Classification |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| menu | pass | 0 | 16.0 | 7.49/8.65 ms | 0/0 | 0 us | 598 us | 0 | 0 | 10456105/0 | 0/0 | 0/0 | first_resource_load |
| small | pass | 1 | 22.2 | 8.02/14.16 ms | 0/0 | 523 us | 1141 us | 0 | 0 | 10456105/0 | 1023/384 | 0/0 | first_resource_load |
