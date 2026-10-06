# singularity-clock

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

A clock app for the [Singularity Desktop Environment](https://github.com/singularityos-lab): alarms, world clocks, a stopwatch and a timer.

Alarms and timers ring even when the Clock window is closed: the app starts in the background at login and keeps running while an alarm is enabled or a timer is counting.

## Pomodoro

The Timer view and the Timer tile in quick settings start a Pomodoro: a focus session, then a short break, and a long break after every fourth session. Lengths are set in Settings, Apps, Clock. While a timer or a Pomodoro runs, the Timer tile shows it and a countdown appears in the panel; click it to pause, resume or cancel.

## Timers over D-Bus

Clock exports its timers on the session bus, so the shell, widgets and other apps can show and control them. The bus name is `dev.sinty.clock` and the object is `/dev/sinty/clock`. The name is D-Bus activatable: calling `Start` or `StartPomodoro` starts Clock in the background if it is not running. Use `NO_AUTO_START` for calls that only read.

Interface `dev.sinty.Clock.Timers`, version 1:

| Member | Signature | Meaning |
| --- | --- | --- |
| `ListTimers` | `() -> a(sssxxx)` | Active timers as (id, kind, state, end time, remaining, duration). Empty when nothing runs. |
| `Start` | `(i seconds) -> s id` | Start a countdown of 1 second to 24 hours. |
| `StartPomodoro` | `() -> s id` | Start a Pomodoro with a focus session. |
| `Pause`, `Resume`, `Cancel` | `(s id)` | Control a timer; an unknown id fails with `InvalidArgs`. |
| `Changed` | signal `(s id, s kind, s state, x end_time, x remaining, x duration)` | Sent when a timer starts, pauses, resumes, stops or moves to the next Pomodoro phase. |
| `Finished` | signal `(s id, s kind)` | Sent when a countdown reaches zero. |
| `Version` | property `u` | Interface version. |

- `kind` is `timer`, `focus`, `short-break` or `long-break`.
- `state` is `running`, `paused` or `idle`.
- Times are in microseconds. `end_time` is wall clock time (`g_get_real_time`) and is zero unless the timer runs; compute the countdown from it instead of polling. `remaining` is valid while paused.
- Clock has one timer today, with id `main`. Clients must still read the id from `ListTimers` and the signals.

The shell integration lives in `plugin/`: a quick settings tile and a panel countdown that use only this interface.

## Requirements

- [Meson](https://mesonbuild.com/) ≥ 1.0
- [Vala](https://vala.dev/) compiler
- [Vetro](https://github.com/singularityos-lab/vetro/) compiler
- GTK4
- libgee-0.8
- [libsingularity](https://github.com/singularityos-lab/libsingularity)

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## License

GPL-3.0-only - see [LICENSE](LICENSE).
