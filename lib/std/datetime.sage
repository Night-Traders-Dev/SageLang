gc_disable()
# Date and time library
# Timestamp arithmetic, formatting, parsing, and timezone offsets

import math

# Days in each month (non-leap year)
let MONTH_DAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
let MONTH_NAMES = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
let MONTH_SHORT = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
let DAY_NAMES = ["Thursday", "Friday", "Saturday", "Sunday", "Monday", "Tuesday", "Wednesday"]
let DAY_SHORT = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"]

# Seconds constants
let MINUTE = 60
let HOUR = 3600
let DAY = 86400
let WEEK = 604800

proc is_leap_year(year):
    if (year & 3) != 0:
        return false
    if year - ((year / 100) | 0) * 100 == 0:
        if year - ((year / 400) | 0) * 400 == 0:
            return true
        return false
    return true

proc days_in_month(year, month):
    if month == 2 and is_leap_year(year):
        return 29
    return MONTH_DAYS[month]

proc days_in_year(year):
    if is_leap_year(year):
        return 366
    return 365

# Create a datetime dict
proc create(year, month, day, hour, minute, second):
    let dt = {}
    dt["year"] = year
    dt["month"] = month
    dt["day"] = day
    dt["hour"] = hour
    dt["minute"] = minute
    dt["second"] = second
    return dt

# Create date only
proc date(year, month, day):
    return create(year, month, day, 0, 0, 0)

# Create time only
proc time(hour, minute, second):
    return create(1970, 1, 1, hour, minute, second)

# Convert datetime to Unix timestamp (seconds since 1970-01-01 00:00:00 UTC)
proc to_timestamp(dt):
    let year = dt["year"]
    let days = 0
    # Count days from 1970 to year
    let y = 1970
    while y < year:
        days = days + days_in_year(y)
        y = y + 1
    # Add days for months in current year
    let m = 1
    while m < dt["month"]:
        days = days + days_in_month(year, m)
        m = m + 1
    days = days + dt["day"] - 1
    return days * 86400 + dt["hour"] * 3600 + dt["minute"] * 60 + dt["second"]

# Convert Unix timestamp to datetime
proc from_timestamp(ts):
    let remaining = ts
    let year = 1970
    while remaining >= days_in_year(year) * 86400:
        remaining = remaining - days_in_year(year) * 86400
        year = year + 1
    let month = 1
    while month <= 12 and remaining >= days_in_month(year, month) * 86400:
        remaining = remaining - days_in_month(year, month) * 86400
        month = month + 1
    let day = (remaining / 86400) | 0
    remaining = remaining - day * 86400
    let hour = (remaining / 3600) | 0
    remaining = remaining - hour * 3600
    let minute = (remaining / 60) | 0
    let second = remaining - minute * 60
    return create(year, month, day + 1, hour, minute, second)

# Day of week (0=Monday, 6=Sunday) for a given date
proc weekday(dt):
    let ts = to_timestamp(dt)
    let days = (ts / 86400) | 0
    # 1970-01-01 was Thursday (index 3 if Monday=0)
    return (days + 3) - (((days + 3) / 7) | 0) * 7

proc weekday_name(dt):
    let wd = weekday(dt)
    let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    return names[wd]

# Pad number with leading zero
proc pad2(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

proc pad4(n):
    if n < 10:
        return "000" + str(n)
    if n < 100:
        return "00" + str(n)
    if n < 1000:
        return "0" + str(n)
    return str(n)

# Format datetime as ISO 8601
proc to_iso(dt):
    return pad4(dt["year"]) + "-" + pad2(dt["month"]) + "-" + pad2(dt["day"]) + "T" + pad2(dt["hour"]) + ":" + pad2(dt["minute"]) + ":" + pad2(dt["second"])

# Format date only
proc to_date_string(dt):
    return pad4(dt["year"]) + "-" + pad2(dt["month"]) + "-" + pad2(dt["day"])

# Format time only
proc to_time_string(dt):
    return pad2(dt["hour"]) + ":" + pad2(dt["minute"]) + ":" + pad2(dt["second"])

# Human-readable format
proc to_string(dt):
    return MONTH_SHORT[dt["month"]] + " " + str(dt["day"]) + ", " + str(dt["year"]) + " " + to_time_string(dt)

# Add duration to datetime
proc add_seconds(dt, secs):
    return from_timestamp(to_timestamp(dt) + secs)

proc add_minutes(dt, mins):
    return add_seconds(dt, mins * 60)

proc add_hours(dt, hrs):
    return add_seconds(dt, hrs * 3600)

proc add_days(dt, d):
    return add_seconds(dt, d * 86400)

# Difference in seconds between two datetimes
proc diff_seconds(a, b):
    return to_timestamp(a) - to_timestamp(b)

proc diff_days(a, b):
    return (diff_seconds(a, b) / 86400) | 0

# Compare datetimes
proc before(a, b):
    return to_timestamp(a) < to_timestamp(b)

proc after(a, b):
    return to_timestamp(a) > to_timestamp(b)

proc equal(a, b):
    return to_timestamp(a) == to_timestamp(b)

# Parse ISO 8601 date string "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM:SS"
proc parse_iso(s):
    let year = tonumber(s[0] + s[1] + s[2] + s[3])
    let month = tonumber(s[5] + s[6])
    let day = tonumber(s[8] + s[9])
    if len(s) >= 19:
        let hour = tonumber(s[11] + s[12])
        let minute = tonumber(s[14] + s[15])
        let second = tonumber(s[17] + s[18])
        return create(year, month, day, hour, minute, second)
    return date(year, month, day)

# Get current time via sys.clock (seconds since epoch, approximate)
proc now_timestamp():
    import sys
    return sys.clock()
