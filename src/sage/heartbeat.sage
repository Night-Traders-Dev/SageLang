gc_disable()
# -----------------------------------------
# heartbeat.sage - Heartbeat/monitoring system for SageLang
# Port of src/c/heartbeat.c (desktop/Linux variant)
#
# Provides a simple heartbeat mechanism for monitoring
# long-running Sage programs. Since Sage doesn't have
# direct thread creation, this implements a cooperative
# heartbeat that must be called periodically from the
# main loop.
# -----------------------------------------

let NL = chr(10)

# -----------------------------------------
# HeartbeatSystem - cooperative heartbeat monitor
#
# Usage:
#   let hb = HeartbeatSystem("my-app")
#   hb.init()
#   while running:
#       hb.update()
#       ... do work ...
#   hb.print_stats()
# -----------------------------------------
class HeartbeatSystem:
    proc init(name):
        self.name = name
        self.call_count = 0
        self.total_calls = 0
        self.report_interval = 100
        self.is_running = false
        self.last_report = 0
        self.reports_made = 0

    proc start():
        self.is_running = true
        self.call_count = 0
        self.total_calls = 0
        self.reports_made = 0

    proc stop():
        self.is_running = false

    proc set_interval(n):
        if n > 0:
            self.report_interval = n

    proc update():
        if self.is_running == false:
            return false
        self.call_count = self.call_count + 1
        self.total_calls = self.total_calls + 1
        if self.call_count >= self.report_interval:
            self.reports_made = self.reports_made + 1
            self.call_count = 0
            return true
        return false

    proc is_alive():
        return self.is_running

    proc get_total_calls():
        return self.total_calls

    proc get_report_count():
        return self.reports_made

    proc print_stats():
        print "=== Heartbeat Stats ==="
        print "Name:           " + self.name
        if self.is_running:
            print "Status:         Running"
        else:
            print "Status:         Stopped"
        print "Total calls:    " + str(self.total_calls)
        print "Reports made:   " + str(self.reports_made)
        print "Report interval: " + str(self.report_interval)
        print "========================"

    proc to_string():
        let status = "stopped"
        if self.is_running:
            status = "running"
        return "Heartbeat(" + self.name + ", " + status + ", calls=" + str(self.total_calls) + ")"

# -----------------------------------------
# HealthCheck - simple health check aggregator
# Monitors multiple named checks and reports overall status
# -----------------------------------------
class HealthCheck:
    proc init():
        self.checks = {}
        self.check_count = 0

    proc register(name, initial_status):
        self.checks[name] = initial_status
        self.check_count = self.check_count + 1

    proc update(name, status):
        if dict_has(self.checks, name):
            self.checks[name] = status
            return true
        return false

    proc get(name):
        if dict_has(self.checks, name):
            return self.checks[name]
        return nil

    proc all_healthy():
        let keys = dict_keys(self.checks)
        let i = 0
        while i < len(keys):
            let k = keys[i]
            if self.checks[k] != true:
                return false
            i = i + 1
        return true

    proc unhealthy_checks():
        let result = []
        let keys = dict_keys(self.checks)
        let i = 0
        while i < len(keys):
            let k = keys[i]
            if self.checks[k] != true:
                push(result, k)
            i = i + 1
        return result

    proc print_status():
        print "=== Health Check ==="
        let keys = dict_keys(self.checks)
        let i = 0
        while i < len(keys):
            let k = keys[i]
            let status = "FAIL"
            if self.checks[k] == true:
                status = "OK"
            print "  " + k + ": " + status
            i = i + 1
        if self.all_healthy():
            print "Overall: HEALTHY"
        else:
            print "Overall: UNHEALTHY"
        print "====================="
