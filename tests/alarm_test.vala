using Singularity.Apps;

private DateTime at(int year, int month, int day, int hour, int minute) {
    return new DateTime.local(year, month, day, hour, minute, 0);
}

private void assert_date(DateTime value, int year, int month, int day, int hour, int minute) {
    assert(value.get_year() == year);
    assert(value.get_month() == month);
    assert(value.get_day_of_month() == day);
    assert(value.get_hour() == hour);
    assert(value.get_minute() == minute);
}

private void test_once_later_today() {
    assert_date(Alarm.next_occurrence(7, 30, 0, at(2026, 9, 25, 6, 0)), 2026, 9, 25, 7, 30);
}

private void test_once_rolls_to_tomorrow() {
    assert_date(Alarm.next_occurrence(7, 30, 0, at(2026, 9, 25, 7, 30)), 2026, 9, 26, 7, 30);
}

private void test_weekdays_skip_weekend() {
    assert_date(Alarm.next_occurrence(7, 0, Alarm.WEEKDAYS, at(2026, 9, 25, 8, 0)), 2026, 9, 28, 7, 0);
}

private void test_single_weekday() {
    uint sunday = Alarm.MONDAY << 6;
    assert_date(Alarm.next_occurrence(9, 15, sunday, at(2026, 9, 25, 12, 0)), 2026, 9, 27, 9, 15);
}

private void test_same_day_next_week() {
    uint friday = Alarm.MONDAY << 4;
    assert_date(Alarm.next_occurrence(6, 0, friday, at(2026, 9, 25, 6, 0)), 2026, 10, 2, 6, 0);
}

private void test_days_text() {
    assert(new Alarm("a", 7, 0, 0, "", true).days_text() == "Once");
    assert(new Alarm("b", 7, 0, Alarm.WEEKDAYS, "", true).days_text() == "Weekdays");
    assert(new Alarm("c", 7, 0, Alarm.MONDAY | (Alarm.MONDAY << 2), "", true).days_text() == "Mon, Wed");
}

public int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/alarm/once-later-today", test_once_later_today);
    Test.add_func("/alarm/once-rolls-to-tomorrow", test_once_rolls_to_tomorrow);
    Test.add_func("/alarm/weekdays-skip-weekend", test_weekdays_skip_weekend);
    Test.add_func("/alarm/single-weekday", test_single_weekday);
    Test.add_func("/alarm/same-day-next-week", test_same_day_next_week);
    Test.add_func("/alarm/days-text", test_days_text);
    return Test.run();
}
