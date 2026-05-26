package android

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/kianmhz/GooseRelayVPN/internal/carrier"
	"github.com/kianmhz/GooseRelayVPN/internal/config"
	"github.com/kianmhz/GooseRelayVPN/internal/session"
	"github.com/kianmhz/GooseRelayVPN/internal/socks"
	"github.com/xjasonlyu/tun2socks/v2/engine"
)

var (
	carr       *carrier.Client
	carrMu     sync.RWMutex
	cancelVpn  context.CancelFunc
	vpnCtx     context.Context
	lastPingMs int64  = -1
	vpnState   string = "stopped"
)

func checkInternet(googleIP string) bool {
	var targets []string
	if googleIP != "" {
		targets = append(targets, googleIP)
	}
	// Try HTTP/HTTPS ports which are less likely to be blocked, and fallback to port 53 TCP
	targets = append(targets, "google.com:80", "google.com:443", "1.1.1.1:53", "8.8.8.8:53")

	for _, target := range targets {
		conn, err := net.DialTimeout("tcp", target, 3*time.Second)
		if err == nil {
			conn.Close()
			return true
		}
	}
	return false
}

// TriggerPing measures the ping in a background goroutine and updates lastPingMs.
func TriggerPing() {
	carrMu.RLock()
	client := carr
	ctx := vpnCtx
	state := vpnState
	carrMu.RUnlock()
	if client == nil || ctx == nil || state != "connected" {
		return
	}
	go func() {
		if d, err := client.MeasurePingManual(ctx); err == nil {
			atomic.StoreInt64(&lastPingMs, d.Milliseconds())
		} else {
			atomic.StoreInt64(&lastPingMs, -1)
		}
	}()
}

// StartVPN starts the VPN SOCKS proxy on 127.0.0.1:1080 (or as configured)
// configJson is the client_config.json string.
func StartVPN(configJson string, cacheDir string) string {
	carrMu.RLock()
	isRunning := carr != nil
	carrMu.RUnlock()
	if isRunning {
		return "Already running"
	}

	// Write config to temp file to use existing LoadClient
	configPath := filepath.Join(cacheDir, "client_config_temp.json")
	if err := os.WriteFile(configPath, []byte(configJson), 0644); err != nil {
		return "Error writing config: " + err.Error()
	}
	defer os.Remove(configPath)

	cfg, err := config.LoadClient(configPath)
	if err != nil {
		return "Config error: " + err.Error()
	}

	c, err := carrier.New(carrier.Config{
		ScriptURLs:         cfg.ScriptURLs,
		ScriptAccounts:     cfg.ScriptAccounts,
		AESKeyHex:          cfg.AESKeyHex,
		DebugTiming:        cfg.DebugTiming,
		ClientVersion:      "flutter-android-dev",
		CoalesceStep:       time.Duration(cfg.CoalesceStepMs) * time.Millisecond,
		CoalesceMax:        time.Duration(cfg.CoalesceMaxMs) * time.Millisecond,
		IdleSlotsPerBucket: cfg.IdleSlotsPerBucket,
		Fronting: carrier.FrontingConfig{
			GoogleIP: cfg.GoogleIP,
			SNIHosts: cfg.SNIHosts,
		},
	})
	if err != nil {
		return "Carrier error: " + err.Error()
	}

	carrMu.Lock()
	carr = c
	ctx, cancel := context.WithCancel(context.Background())
	vpnCtx = ctx
	cancelVpn = cancel
	vpnState = "checking_internet"
	carrMu.Unlock()

	atomic.StoreInt64(&lastPingMs, -1)

	factory := socks.SessionFactory(func(target string) *session.Session {
		carrMu.RLock()
		client := carr
		carrMu.RUnlock()
		if client == nil {
			return nil
		}
		return client.NewSession(target)
	})

	go func() {
		// 1. Check internet connection
		if !checkInternet(cfg.GoogleIP) {
			carrMu.Lock()
			vpnState = "failed: No internet connection"
			if cancelVpn != nil {
				cancelVpn()
				cancelVpn = nil
			}
			carr = nil
			carrMu.Unlock()
			return
		}

		// 2. Checking relay connection (pre-flight checks)
		carrMu.Lock()
		if ctx.Err() != nil {
			carrMu.Unlock()
			return
		}
		vpnState = "checking_relay"
		client := carr
		carrMu.Unlock()

		if client != nil {
			diagCtx, cancelDiag := context.WithTimeout(ctx, 15*time.Second)
			err := client.Diagnose(diagCtx)
			cancelDiag()
			if err != nil {
				carrMu.Lock()
				vpnState = "failed: Relay connection failed"
				if cancelVpn != nil {
					cancelVpn()
					cancelVpn = nil
				}
				carr = nil
				carrMu.Unlock()
				return
			}
		}

		// 3. Setup running/connected state
		carrMu.Lock()
		if ctx.Err() != nil {
			carrMu.Unlock()
			return
		}
		vpnState = "connected"
		client = carr
		carrMu.Unlock()

		if client != nil {
			go func() {
				_ = client.Run(ctx)
			}()

			go func() {
				_ = socks.Serve(ctx, cfg.ListenAddr, cfg.SocksUser, cfg.SocksPass, cfg.DebugTiming, factory)
			}()

			// Run a single manual ping check on startup
			if d, err := client.MeasurePingManual(ctx); err == nil {
				atomic.StoreInt64(&lastPingMs, d.Milliseconds())
			}
		}
	}()

	return "OK"
}

// StopVPN stops the running VPN proxy
func StopVPN() {
	carrMu.Lock()
	defer carrMu.Unlock()
	vpnState = "stopped"
	if cancelVpn != nil {
		if carr != nil {
			shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 3*time.Second)
			carr.Shutdown(shutdownCtx)
			shutdownCancel()
		}
		cancelVpn()
		carr = nil
		cancelVpn = nil
	}
}

func GetStatsJSON() string {
	carrMu.RLock()
	state := vpnState
	client := carr
	carrMu.RUnlock()

	type StatsResponse struct {
		Status       string                 `json:"status"`
		BytesIn      uint64                 `json:"bytes_in"`
		BytesOut     uint64                 `json:"bytes_out"`
		DailyCount   uint64                 `json:"daily_count"`
		ScriptCount  uint64                 `json:"script_count"`
		Ping         int64                  `json:"ping"`
		Endpoints    []carrier.EndpointStat `json:"endpoints"`
	}

	if client == nil {
		res := StatsResponse{
			Status: state,
			Ping:   -1,
			Endpoints: []carrier.EndpointStat{},
		}
		b, _ := json.Marshal(res)
		return string(b)
	}

	bytesIn, bytesOut, dailyCount, scriptCount := client.GetStats()
	pingVal := atomic.LoadInt64(&lastPingMs)
	endpoints := client.GetEndpointStats()

	res := StatsResponse{
		Status:      state,
		BytesIn:     bytesIn,
		BytesOut:    bytesOut,
		DailyCount:  dailyCount,
		ScriptCount: scriptCount,
		Ping:        pingVal,
		Endpoints:   endpoints,
	}
	b, _ := json.Marshal(res)
	return string(b)
}

// StartTun2Socks starts the tun2socks bridge
func StartTun2Socks(fd int64, socksAddr string) string {
	key := &engine.Key{
		Proxy:    "socks5://" + socksAddr,
		Device:   fmt.Sprintf("fd://%d", fd),
		LogLevel: "info",
		MTU:      1500,
	}
	engine.Insert(key)
	engine.Start()
	return "OK"
}

// StopTun2Socks stops the tun2socks bridge
func StopTun2Socks() {
	engine.Stop()
}

