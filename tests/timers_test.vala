using Singularity.Apps;

private void test_countdown() {
    assert(TimerText.countdown(0) == "00:00");
    assert(TimerText.countdown(1) == "00:01");
    assert(TimerText.countdown(TimeSpan.SECOND) == "00:01");
    assert(TimerText.countdown(299 * TimeSpan.SECOND + 1) == "05:00");
    assert(TimerText.countdown(3723 * TimeSpan.SECOND) == "1:02:03");
    assert(TimerText.countdown(-5) == "00:00");
}

private void test_compact() {
    assert(TimerText.compact(59 * TimeSpan.SECOND) == "0:59");
    assert(TimerText.compact(25 * 60 * TimeSpan.SECOND) == "25:00");
    assert(TimerText.compact(3600 * TimeSpan.SECOND) == "1:00:00");
}

private void test_remaining() {
    assert(TimerText.remaining("running", 10000, 0, 4000) == 6000);
    assert(TimerText.remaining("running", 10000, 0, 12000) == 0);
    assert(TimerText.remaining("paused", 0, 777, 12000) == 777);
    assert(TimerText.remaining("idle", 10000, 777, 0) == 0);
    assert(TimerText.fraction(50, 100) == 0.5);
    assert(TimerText.fraction(50, 0) == 0.0);
    assert(TimerText.fraction(150, 100) == 1.0);
}

private void test_kinds() {
    foreach (var k in new TimerKind[] { TimerKind.TIMER, TimerKind.FOCUS, TimerKind.SHORT_BREAK, TimerKind.LONG_BREAK }) {
        assert(TimerKind.from_id(k.to_id()) == k);
    }
    assert(TimerKind.from_id("bogus") == TimerKind.TIMER);
    assert(!TimerKind.TIMER.is_pomodoro());
    assert(TimerKind.LONG_BREAK.is_break());
    assert(!TimerKind.FOCUS.is_break());
}

private void test_pomodoro() {
    var cycle = new PomodoroCycle();
    assert(cycle.minutes_for(TimerKind.FOCUS) == 25);
    assert(cycle.minutes_for(TimerKind.SHORT_BREAK) == 5);
    assert(cycle.minutes_for(TimerKind.LONG_BREAK) == 15);
    TimerKind next;
    assert(!cycle.next_after(TimerKind.TIMER, out next));
    assert(!cycle.next_after(TimerKind.SHORT_BREAK, out next));
    for (int round = 1; round <= 8; round++) {
        assert(cycle.next_after(TimerKind.FOCUS, out next));
        assert(next == (round % 4 == 0 ? TimerKind.LONG_BREAK : TimerKind.SHORT_BREAK));
    }
    assert(cycle.completed == 8);
    cycle.reset();
    assert(cycle.completed == 0);
    cycle.rounds_before_long_break = 0;
    assert(cycle.next_after(TimerKind.FOCUS, out next) && next == TimerKind.LONG_BREAK);
}

public static int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/timers/countdown", test_countdown);
    Test.add_func("/timers/compact", test_compact);
    Test.add_func("/timers/remaining", test_remaining);
    Test.add_func("/timers/kinds", test_kinds);
    Test.add_func("/timers/pomodoro", test_pomodoro);
    return Test.run();
}
