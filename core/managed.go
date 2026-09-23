package main

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/metacubex/mihomo/tunnel/statistic"
)

type managedRequest struct {
	Operation      string              `json:"operation"`
	Tags           map[string]string   `json:"tags"`
	Remaining      int64               `json:"remaining"`
	TTL            int64               `json:"ttl"`
	Confirmed      map[string][2]int64 `json:"confirmed"`
	Reason         string              `json:"reason"`
	DeadlineReason string              `json:"deadline_reason"`
	ControlHosts   []string            `json:"control_hosts"`
}

func handleManagedSession(data string) string {
	var request managedRequest
	if err := json.Unmarshal([]byte(data), &request); err != nil {
		return `{"error":"invalid_request"}`
	}
	ttl := request.TTL
	if ttl < 0 {
		ttl = 0
	}
	if ttl > 300 {
		ttl = 300
	}
	switch request.Operation {
	case "control":
		statistic.Managed.ControlHosts(request.ControlHosts)
	case "begin":
		_ = handleCloseConnections()
		statistic.Managed.Begin(request.Tags, request.Remaining, time.Duration(ttl)*time.Second)
		statistic.Managed.DeadlineReason(request.DeadlineReason)
	case "renew":
		statistic.Managed.Renew(request.Remaining, time.Duration(ttl)*time.Second, request.Confirmed)
		statistic.Managed.DeadlineReason(request.DeadlineReason)
	case "stop":
		statistic.Managed.Stop(request.Reason)
		_ = handleCloseConnections()
		_ = handleStopListener()
	case "snapshot", "capabilities":
	default:
		return `{"error":"invalid_operation"}`
	}
	totals, reason := statistic.Managed.Snapshot()
	remaining, active := statistic.Managed.Remaining()
	result, _ := json.Marshal(map[string]any{"metering_version": 1, "traffic": totals, "reason": reason, "remaining": remaining, "active": active})
	return string(result)
}

func configureManagedRequirement(proxies []map[string]any) {
	required := false
	for _, proxy := range proxies {
		name, _ := proxy["name"].(string)
		if strings.HasPrefix(name, "upstream-") {
			required = true
			break
		}
	}
	statistic.Managed.Require(required)
}

func init() {
	go func() {
		for range time.NewTicker(time.Second).C {
			if !statistic.Managed.Allowed() {
				_ = handleCloseConnections()
				_ = handleStopListener()
			}
		}
	}()
}
